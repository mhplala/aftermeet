import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreGraphics

/// Streams system audio via ScreenCaptureKit and transcribes it live with a resident
/// whisper-server. All blocking work (WAV write, HTTP inference, server restart) runs on
/// a dedicated serial queue — never the Swift cooperative pool or main — so a slow/wedged
/// server can't freeze the UI. The audio window is hard-capped so memory can't run away.
final class CaptureService: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    @Published var isCapturing = false
    @Published var liveText = ""
    @Published var status = "未开始"
    @Published var elapsed = 0
    @Published var savedPath = ""        // where the live transcript is being written, immediately
    @Published var meetingName = ""      // set by the user (or 豆包 title on stop)
    @Published var calendarSuggestion = "" // best-effort calendar guess — a suggestion, not committed

    private var stream: SCStream?
    private let audioQueue = DispatchQueue(label: "aftermeet.audio")
    private let videoQueue = DispatchQueue(label: "aftermeet.video")
    private let inferQueue = DispatchQueue(label: "aftermeet.infer")   // serial; blocking is OK here
    private let server = WhisperServer()
    private let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("aftermeet-window.wav")

    private var window = [Float]()     // audioQueue
    private var rate: Double = 48_000  // audioQueue
    private var committed = ""         // main
    private var inferring = false      // main
    private var emptyStreak = 0        // inferQueue
    private var lastSegment = ""       // inferQueue — cross-segment de-dup

    private var sessionURL: URL?       // live transcript file — appended every commit, survives a crash
    private var tickTimer: Timer?
    private var clockTimer: Timer?
    private let tickSeconds = 1.5
    private let commitSeconds = 8.0
    private let maxWindowSeconds = 30.0   // hard cap — bounds memory + inference size
    private let speechFloor: Float = 0.010   // per-30ms-frame mean-abs above this counts as voiced (tunable)
    private let minVoicedFrames = 5          // need ~150ms of voiced audio in a window, else it's silence → don't feed whisper

    func requestAuth() { _ = CGRequestScreenCaptureAccess() }

    private var sessionHeaderDate = ""

    // live transcript persistence — append each committed segment to disk immediately
    private func startSession(name: String) -> String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AfterMeet/transcripts")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd-HHmmss"
        let url = dir.appendingPathComponent("会中转写-\(df.string(from: Date())).txt")
        let dd = DateFormatter(); dd.locale = Locale(identifier: "zh_CN"); dd.dateFormat = "M月d日 HH:mm"
        sessionHeaderDate = dd.string(from: Date())
        let title = name.isEmpty ? "未命名会议" : name
        try? "# \(title) · \(sessionHeaderDate)\n\n".data(using: .utf8)?.write(to: url)
        sessionURL = url
        return url.path
    }

    /// User (or calendar) names the meeting — rewrite the file's title line.
    func setMeetingName(_ name: String) {
        DispatchQueue.main.async { self.meetingName = name }
        inferQueue.async {
            guard let url = self.sessionURL,
                  let content = try? String(contentsOf: url, encoding: .utf8) else { return }
            var lines = content.components(separatedBy: "\n")
            let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? "未命名会议" : name
            let header = "# \(title) · \(self.sessionHeaderDate)"
            if lines.isEmpty { lines = [header] } else { lines[0] = header }
            try? lines.joined(separator: "\n").data(using: .utf8)?.write(to: url)
        }
    }

    private func appendToSession(_ text: String) {   // inferQueue
        guard let url = sessionURL, let data = (text + "\n").data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
    }

    // diagnostic log → ~/aftermeet-capture.log
    private let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("aftermeet-capture.log")
    private func dbg(_ s: String, reset: Bool = false) {
        let line = s + "\n"
        if reset { try? line.data(using: .utf8)?.write(to: logURL); return }
        if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
        else { try? line.data(using: .utf8)?.write(to: logURL) }
    }

    // MARK: - Lifecycle

    func start() async {
        await MainActor.run { self.committed = ""; self.liveText = ""; self.elapsed = 0; self.isCapturing = true; self.status = "启动…" }
        guard Whisper.available() else {
            await MainActor.run { self.status = "未找到 whisper-cli/模型（\(Whisper.cli)）"; self.isCapturing = false }
            return
        }
        audioQueue.sync { self.window.removeAll() }
        inferQueue.sync { self.emptyStreak = 0; self.lastSegment = "" }
        dbg("=== start ===", reset: true)
        let detected = LarkCalendar.currentMeetingName() ?? ""   // a suggestion only — not committed
        let path = startSession(name: "")                        // file starts "未命名会议"
        await MainActor.run { self.savedPath = path; self.meetingName = ""; self.calendarSuggestion = detected }
        server.start()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else {
                await MainActor.run { self.status = "找不到可采集的显示器"; self.isCapturing = false }; return
            }
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let cfg = SCStreamConfiguration()
            cfg.capturesAudio = true
            cfg.sampleRate = 16_000
            cfg.channelCount = 1
            cfg.excludesCurrentProcessAudio = true
            cfg.width = 192; cfg.height = 108
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: 2)

            let s = SCStream(filter: filter, configuration: cfg, delegate: self)
            try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
            try await s.startCapture()
            stream = s
            await MainActor.run { self.status = "录制中 · Whisper 流式 · 约 1.5 秒刷新"; self.startTimers() }
        } catch {
            server.stop()
            await MainActor.run { self.status = "需要屏幕录制权限：系统设置 › 隐私与安全性 › 屏幕录制，勾选 AfterMeet 后重开。"; self.isCapturing = false }
        }
    }

    func stop() async -> String {
        let e = await MainActor.run { () -> Int in
            self.tickTimer?.invalidate(); self.tickTimer = nil
            self.clockTimer?.invalidate(); self.clockTimer = nil
            self.status = "结束，整理中…"
            return self.elapsed
        }
        if let s = stream { try? await s.stopCapture() }
        stream = nil
        inferQueue.sync { self.runInferenceSync(forceCommit: true, sessionElapsed: e) }   // final flush
        server.stop()
        return await MainActor.run { () -> String in
            self.isCapturing = false
            self.status = "已结束"
            self.liveText = self.committed
            return self.committed.trimmingCharacters(in: .whitespaces)
        }
    }

    private func startTimers() {
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.isCapturing else { return }
            self.elapsed += 1
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: tickSeconds, repeats: true) { [weak self] _ in
            guard let self, !self.inferring else { return }
            self.inferring = true
            let e = self.elapsed                 // snapshot on main — runInferenceSync runs off-queue
            self.inferQueue.async {
                self.runInferenceSync(forceCommit: false, sessionElapsed: e)
                DispatchQueue.main.async { self.inferring = false }
            }
        }
    }

    // MARK: - Inference (inferQueue, blocking allowed)

    private func runInferenceSync(forceCommit: Bool, sessionElapsed: Int) {
        let (snap, r) = audioQueue.sync { (self.window, self.rate) }
        guard snap.count >= Int(1.0 * r) else { return }

        let tailN = min(snap.count, Int(0.6 * r))
        let tailEnergy = snap.suffix(tailN).reduce(Float(0)) { $0 + abs($1) } / Float(max(tailN, 1))
        let silentTail = tailEnergy < 0.01 && Double(snap.count) >= 1.5 * r
        let shouldCommit = forceCommit || silentTail || Double(snap.count) >= commitSeconds * r
        guard shouldCommit else { return }   // transcribe ONLY at a boundary → ~6× fewer server calls

        let trim = { self.audioQueue.async {
            if snap.count <= self.window.count { self.window.removeFirst(snap.count) } else { self.window.removeAll() }
        } }

        // 静音别喂：扫一遍整窗，凑不够人声帧就根本不调 whisper。whisper 在静音/无语音段会幻觉
        // 训练集里高频的 YouTube 片尾（「请不吝点赞…支持明镜与点点栏目」），必须在喂之前拦住。
        let frameN = max(1, Int(0.03 * r))           // 30ms frames
        var voiced = 0, peak: Float = 0, i = 0
        while i + frameN <= snap.count {
            var e: Float = 0, k = i
            while k < i + frameN { e += abs(snap[k]); k += 1 }
            e /= Float(frameN)
            if e > peak { peak = e }
            if e > speechFloor { voiced += 1 }
            i += frameN
        }
        if voiced < minVoicedFrames {
            dbg(String(format: "t=%ds win=%.1fs peak=%.4f voiced=%d → 跳过(静音不喂)",
                       sessionElapsed, Double(snap.count) / r, peak, voiced))
            trim()                                   // drop the silent window — never reaches whisper
            return
        }

        guard writeWav(snap, rate: r, to: tmp) else { return }
        let t = server.infer(wav: tmp).trimmingCharacters(in: .whitespaces)
        dbg(String(format: "t=%ds win=%.1fs energy=%.4f voiced=%d silent=%@ chars=%d",
                   sessionElapsed, Double(snap.count) / r, tailEnergy, voiced, silentTail ? "Y" : "n", t.count))

        if t.isEmpty {
            if tailEnergy > 0.02 {
                // Speech but no text → server wedged. Restart; keep the (capped) audio for recovery.
                emptyStreak += 1
                if emptyStreak >= 2 {
                    dbg("!! whisper-server wedged — restarting")
                    server.restart()
                    emptyStreak = 0
                    dbg("server restarted")
                }
            } else {
                trim()                               // genuinely quiet → drop the silence
            }
            return
        }
        emptyStreak = 0
        let clean = collapseRepeats(t)
        if clean.isEmpty || clean == lastSegment {   // whole segment is a repeat of the last → drop
            trim(); return
        }
        lastSegment = clean
        appendToSession(clean)                        // persist this segment to disk immediately
        DispatchQueue.main.async {
            self.committed += (self.committed.isEmpty ? "" : " ") + clean
            self.liveText = self.committed
        }
        trim()
    }

    /// Collapse consecutive identical sentences ("X。X。X。" → "X。") — whisper loops on low-info audio.
    private func collapseRepeats(_ text: String) -> String {
        var units: [String] = []
        var cur = ""
        for ch in text {
            cur.append(ch)
            if "。！？\n".contains(ch) { units.append(cur); cur = "" }
        }
        if !cur.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { units.append(cur) }
        var out: [String] = []
        for u in units {
            let n = u.trimmingCharacters(in: .whitespacesAndNewlines)
            if n.isEmpty { continue }
            if let last = out.last, last.trimmingCharacters(in: .whitespacesAndNewlines) == n { continue }
            out.append(u)
        }
        return out.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func writeWav(_ samples: [Float], rate: Double, to url: URL) -> Bool {
        guard !samples.isEmpty,
              let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count))
        else { return false }
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in buf.floatChannelData![0].update(from: src.baseAddress!, count: samples.count) }
        try? FileManager.default.removeItem(at: url)
        do { let f = try AVAudioFile(forWriting: url, settings: fmt.settings); try f.write(from: buf); return true }
        catch { return false }
    }

    // MARK: - SCStreamOutput (audioQueue)

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sb.isValid,
              let asbd = sb.formatDescription?.audioStreamBasicDescription,
              let fmt = AVAudioFormat(standardFormatWithSampleRate: asbd.mSampleRate, channels: asbd.mChannelsPerFrame)
        else { return }
        rate = asbd.mSampleRate
        try? sb.withAudioBufferList { abl, _ in
            guard let pcm = AVAudioPCMBuffer(pcmFormat: fmt, bufferListNoCopy: abl.unsafePointer),
                  let ch = pcm.floatChannelData else { return }
            self.window.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: Int(pcm.frameLength)))
        }
        // hard cap — drop oldest audio so the window (and inference cost) can't run away
        let maxN = Int(maxWindowSeconds * rate)
        if window.count > maxN { window.removeFirst(window.count - maxN) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            self.tickTimer?.invalidate(); self.tickTimer = nil
            self.clockTimer?.invalidate(); self.clockTimer = nil
            self.status = "采集中断：\(error.localizedDescription)"; self.isCapturing = false
        }
    }
}
