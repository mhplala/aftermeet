import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreGraphics

/// Streams system audio via ScreenCaptureKit and transcribes it live. Cloud (Volcengine, via
/// CloudASRSession) is the default path when CloudASRConfig is set — no local CPU/model cost;
/// a resident whisper-server is the offline/failure fallback. All local-path blocking work (WAV
/// write, HTTP inference, server restart) runs on a dedicated serial queue — never the Swift
/// cooperative pool or main — so a slow/wedged server can't freeze the UI. The audio window is
/// hard-capped so memory can't run away.
final class CaptureService: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate, CloudASRSessionDelegate {
    @Published var isCapturing = false
    @Published var liveText = ""
    /// 已定稿的分句（逐条，供实时预览分行渲染）。只用于显示，封顶保留最近若干条；
    /// 完整文稿始终以 committed / 落盘文件为准。
    @Published var liveLines: [String] = []
    /// 正在成形、还可能被服务端改写的那一句（云端 definite=false 的分句）。本地路径为空。
    @Published var pendingLine = ""
    private static let maxLiveLines = 60
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

    // 云端优先：CloudASRConfig 配好就走火山流式识别（省本地性能）。断线先重连、退避重试，
    // 只有重试都失败才退回本地 whisper-server（设置里可以选"永不退回"）。
    private var cloudASR: CloudASRSession?
    /// 暂停：采集流继续跑（避免反复申请权限/重建流），但音频不入窗、不转写、不计时、不落盘。
    @Published private(set) var isPaused = false
    /// audioQueue 私有的暂停镜像。音频回调跑在 audioQueue 上，不能直接读主线程的 @Published
    /// 属性（数据竞争），所以用这个由同一队列串行写入的标志做门禁。
    private var pausedFlag = false
    @Published private(set) var usingCloud = false        // main-thread only — UI 绑定，当前是否在往云端发
    @Published private(set) var cloudReconnecting = false // main — 云端断了、正在退避重连（此间音频只落盘不转写）
    /// main — 本条云端会话里已落盘到的时间点（ms）。靠它去重，而不是数组下标；每建新会话归零。
    private var cloudLastCommittedEnd = 0
    private var cloudSendTimer: Timer?
    private var cloudRetryCount = 0        // main — 连续失败次数，成功收到结果就清零
    private var cloudRetryWork: DispatchWorkItem?
    /// 退避 1/2/4/8/16s 共 ~31s；仍失败才认为"万不得已"，退回本地。
    private static let maxCloudRetries = 5

    private var window = [Float]()     // audioQueue — 系统音频（对方的声音）
    private var rate: Double = 48_000  // audioQueue
    private var micWindow = [Float]()  // audioQueue — 麦克风（你的声音，macOS 15+）
    private var micRate: Double = 16_000
    /// 原始录音使用独立缓冲，绝不依赖 ASR 窗口是否被成功消费。否则本地 Whisper 卡死时，
    /// ASR 窗口触发 hard cap 会先丢掉尚未写盘的旧音频。
    private var backupWindow = [Float]()       // audioQueue
    private var backupMicWindow = [Float]()    // audioQueue
    private var committed = ""         // main
    private var inferring = false      // main
    private var emptyStreak = 0        // inferQueue
    private var lastSegment = ""       // inferQueue — cross-segment de-dup

    private var sessionURL: URL?       // live transcript file — appended every commit, survives a crash
    private var recordingURL: URL?     // raw audio backup — written continuously regardless of whether ASR (cloud or local) succeeds
    private var backupAudioFile: AVAudioFile?    // inferQueue-confined
    private var backupAudioFormat: AVAudioFormat?  // inferQueue-confined
    private var tickTimer: Timer?
    private var clockTimer: Timer?
    private var backupFlushTimer: Timer?
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
        let stamp = df.string(from: Date())
        let url = dir.appendingPathComponent("会中转写-\(stamp).txt")
        let dd = DateFormatter(); dd.locale = Locale(identifier: "zh_CN"); dd.dateFormat = "M月d日 HH:mm"
        sessionHeaderDate = dd.string(from: Date())
        let title = name.isEmpty ? "未命名会议" : name
        try? "# \(title) · \(sessionHeaderDate)\n\n".data(using: .utf8)?.write(to: url)
        sessionURL = url

        let recDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AfterMeet/recordings")
        try? FileManager.default.createDirectory(at: recDir, withIntermediateDirectories: true)
        recordingURL = recDir.appendingPathComponent("会中录音-\(stamp).wav")
        inferQueue.sync {
            backupAudioFile = nil; backupAudioFormat = nil   // 惰性开文件——真收到第一段音频时按实际采样率建
        }

        return url.path
    }

    /// 原始音频持续写盘的安全网——和转写是否成功完全解耦：哪怕云端/本地转写整个失败或假死，
    /// 这份音频还在，之后可以重新转写。惰性建文件（首次写入时才知道实际采样率）。
    /// 调用方必须已经在 inferQueue 上；独立备份入口会先 dispatch 到该队列。
    private func appendBackupAudioLocked(_ samples: [Float], rate: Double) {
        guard !samples.isEmpty, let recordingURL else { return }
        if backupAudioFile == nil {
            guard let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
                  let file = try? AVAudioFile(forWriting: recordingURL, settings: fmt.settings) else { return }
            backupAudioFormat = fmt
            backupAudioFile = file
        }
        guard let file = backupAudioFile, let fmt = backupAudioFormat,
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in buf.floatChannelData![0].update(from: src.baseAddress!, count: samples.count) }
        try? file.write(from: buf)
    }

    /// backupFlushTimer（main）调这个非阻塞入口。
    private func appendBackupAudio(_ samples: [Float], rate: Double) {
        guard !samples.isEmpty else { return }
        inferQueue.async { self.appendBackupAudioLocked(samples, rate: rate) }
    }

    /// User (or calendar) names the meeting — rewrite the file's title line.
    func setMeetingName(_ name: String) {
        DispatchQueue.main.async { self.meetingName = name }
        let url = sessionURL                    // 调用时快照，不能等队列执行时再读当前会话
        let headerDate = sessionHeaderDate
        inferQueue.async {
            guard let url else { return }
            self.rewriteSessionTitleLocked(name, at: url, fallbackDate: headerDate)
        }
    }

    /// 会后异步提炼可能在下一场录制已经开始后才拿到标题；必须显式传旧文件路径，不能再碰当前 sessionURL。
    func setStoredMeetingName(_ name: String, transcriptPath: String) {
        let url = URL(fileURLWithPath: transcriptPath)
        inferQueue.async { self.rewriteSessionTitleLocked(name, at: url, fallbackDate: nil) }
    }

    private func rewriteSessionTitleLocked(_ name: String, at url: URL, fallbackDate: String?) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        var lines = content.components(separatedBy: "\n")
        let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? "未命名会议" : name
        let existing = lines.first ?? ""
        let suffix = existing.range(of: " · ").map { String(existing[$0.lowerBound...]) }
            ?? fallbackDate.map { " · \($0)" } ?? ""
        let header = "# \(title)\(suffix)"
        if lines.isEmpty { lines = [header] } else { lines[0] = header }
        try? lines.joined(separator: "\n").data(using: .utf8)?.write(to: url)
    }

    private func appendToSession(_ text: String, at url: URL) {   // inferQueue
        guard let data = (text + "\n").data(using: .utf8) else { return }
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
        await MainActor.run {
            self.committed = ""; self.liveText = ""; self.liveLines = []; self.pendingLine = ""
            self.elapsed = 0; self.isCapturing = true; self.isPaused = false; self.status = "启动…"
        }
        let cloudReady = CloudASRConfig.isConfigured
        guard cloudReady || Whisper.available() else {
            await MainActor.run { self.status = "未配置云端转写，也未找到本地 whisper-cli/模型（\(Whisper.cli)）"; self.isCapturing = false }
            return
        }
        audioQueue.sync {
            self.pausedFlag = false
            self.window.removeAll(); self.micWindow.removeAll()
            self.backupWindow.removeAll(); self.backupMicWindow.removeAll()
        }
        inferQueue.sync { self.emptyStreak = 0; self.lastSegment = "" }
        cloudLastCommittedEnd = 0
        cloudRetryCount = 0
        cloudRetryWork?.cancel(); cloudRetryWork = nil
        cloudReconnecting = false
        dbg("=== start ===", reset: true)
        let detected = LarkCalendar.currentMeetingName() ?? ""   // a suggestion only — not committed
        let path = startSession(name: "")                        // file starts "未命名会议"
        await MainActor.run { self.savedPath = path; self.meetingName = ""; self.calendarSuggestion = detected }
        if cloudReady { startCloudASR() } else { startLocalFallback() }
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
            if #available(macOS 15.0, *) {
                cfg.captureMicrophone = true          // 你的发言也进逐字稿（首次会弹麦克风授权）
                // 明确指定麦克风，默认避开蓝牙：一旦打开蓝牙耳机的麦克风，macOS 会把耳机
                // 从 A2DP 切到 HFP，整条链路掉到 16kHz 电话音质，且 HFP 的 AGC 会把电平顶到削顶。
                if let uid = AudioInputDevices.resolvedDeviceUID() {
                    cfg.microphoneCaptureDeviceID = uid
                    dbg("[mic] 指定输入设备 uid=\(uid)")
                } else {
                    dbg("[mic] 跟随系统默认输入")
                }
            }

            let s = SCStream(filter: filter, configuration: cfg, delegate: self)
            try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
            if #available(macOS 15.0, *) {
                try? s.addStreamOutput(self, type: .microphone, sampleHandlerQueue: audioQueue)
            }
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
            try await s.startCapture()
            stream = s
            await MainActor.run {
                self.status = self.usingCloud ? "录制中 · 云端转写 · 实时" : "录制中 · Whisper 流式 · 约 1.5 秒刷新"
                self.startTimers()
            }
        } catch {
            cloudASR?.cancel(); cloudASR = nil
            server.stop()
            await MainActor.run { self.status = "需要屏幕录制权限：系统设置 › 隐私与安全性 › 屏幕录制，勾选 AfterMeet 后重开。"; self.isCapturing = false }
        }
    }

    /// 建立（或重建）云端会话。任何失败都汇到 handleCloudFailure，由它决定重连还是退回本地。
    private func startCloudASR() {
        let session = CloudASRSession()
        session.delegate = self
        cloudASR = session
        // 新会话的时间轴从 0 重新开始，去重水位必须跟着归零，
        // 否则新会话所有分句的 endTime 都小于旧水位，一句都提交不了。
        cloudLastCommittedEnd = 0
        do {
            try session.open()
            usingCloud = true
            cloudReconnecting = false
            if cloudRetryCount > 0 {
                dbg("cloud reconnected (attempt \(cloudRetryCount))")
                status = "已重连云端 · 实时转写"
            }
            // 注意：这里不清零 cloudRetryCount —— 握手成功不等于链路通，
            // 必须等真收到识别结果（cloudASR(_:didUpdate:)）才算数，否则"连上就断"会无限重试。
        } catch {
            session.cancel()        // open 半路失败也要收表，别把带活定时器的会话直接丢掉
            cloudASR = nil
            handleCloudFailure(reason: (error as NSError).localizedDescription)
        }
    }

    /// 云端出问题时的唯一入口：先退避重连，重试都用光了才退回本地（设置里可选"永不退回"）。
    private func handleCloudFailure(reason: String) {
        guard isCapturing else { return }
        cloudRetryCount += 1
        usingCloud = false
        cloudRetryWork?.cancel()

        let exhausted = cloudRetryCount > Self.maxCloudRetries
        if exhausted && !CloudASRConfig.neverFallbackToLocal {
            cloudReconnecting = false
            dbg("!! cloud failed \(cloudRetryCount)x (\(reason)) — falling back to local")
            startLocalFallback()
            status = Whisper.available() ? "云端多次重连失败，已切换本地 · Whisper 流式"
                                         : "云端多次重连失败，且未安装本地转写引擎"
            return
        }

        // 重连期间音频由独立备份缓冲照常落盘，只是暂时不转写 —— 会留一小段空白，
        // 但比"整场会降级到本地"划算得多。
        cloudReconnecting = true
        let delay = min(pow(2.0, Double(cloudRetryCount - 1)), 30)   // 1,2,4,8,16…封顶 30s
        dbg("cloud failed (\(reason)) — reconnect #\(cloudRetryCount) in \(Int(delay))s")
        status = "云端中断，\(Int(delay))秒后重连…（第 \(cloudRetryCount) 次）"
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isCapturing, self.cloudReconnecting else { return }
            self.startCloudASR()
        }
        cloudRetryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - 暂停 / 继续

    func pause() {
        guard isCapturing, !isPaused else { return }
        isPaused = true
        flushBackupAudio()        // 先把暂停前的原始音频落盘，再清缓冲
        // 云端会话必须收掉：火山对客户端有 8 秒"等包超时"，暂停期间不发包会被服务端判死，
        // 反而触发一轮无谓的重连。继续时重新建会话即可（时间水位按会话归零，已处理）。
        if usingCloud, let cloud = cloudASR {
            flushToCloud()          // 暂停前把窗里剩的音频送完，别丢半句
            cloud.finish()
            cloud.cancel()
            cloudASR = nil
        }
        usingCloud = false
        cloudRetryWork?.cancel(); cloudRetryWork = nil
        cloudReconnecting = false
        server.stop()               // 本地路径同理，别让引擎空转
        audioQueue.async {
            self.pausedFlag = true
            self.window.removeAll(); self.micWindow.removeAll()
            self.backupWindow.removeAll(); self.backupMicWindow.removeAll()
        }
        pendingLine = ""
        status = "已暂停"
        dbg("=== paused ===")
    }

    func resume() {
        guard isCapturing, isPaused else { return }
        isPaused = false
        audioQueue.async {
            self.pausedFlag = false
            self.window.removeAll(); self.micWindow.removeAll()
            self.backupWindow.removeAll(); self.backupMicWindow.removeAll()
        }
        cloudRetryCount = 0
        dbg("=== resumed ===")
        if CloudASRConfig.isConfigured { startCloudASR() } else { startLocalFallback() }
        status = usingCloud ? "录制中 · 云端转写 · 实时" : "录制中 · Whisper 流式"
    }

    func togglePause() { isPaused ? resume() : pause() }

    private func startLocalFallback() {
        usingCloud = false
        cloudReconnecting = false
        cloudRetryWork?.cancel(); cloudRetryWork = nil
        guard Whisper.available() else { return }   // 顶部 guard 已经保证至少一条路可用；这里单纯没有本地模型就不启动
        server.start()
    }

    func stop() async -> String {
        let (e, wasReconnecting) = await MainActor.run { () -> (Int, Bool) in
            self.tickTimer?.invalidate(); self.tickTimer = nil
            self.clockTimer?.invalidate(); self.clockTimer = nil
            self.backupFlushTimer?.invalidate(); self.backupFlushTimer = nil
            self.cloudSendTimer?.invalidate(); self.cloudSendTimer = nil
            self.cloudRetryWork?.cancel(); self.cloudRetryWork = nil   // 别让待触发的重连在收尾后又把会话拉起来
            let reconnecting = self.cloudReconnecting
            self.cloudReconnecting = false
            self.status = "结束，整理中…"
            return (self.elapsed, reconnecting)
        }
        if let s = stream { try? await s.stopCapture() }
        stream = nil
        flushBackupAudio()                 // stream 停稳后收掉最后一小段原始音频
        if usingCloud, let cloud = cloudASR {
            flushToCloud()                 // 把窗口里剩的最后一点音频也发过去
            cloud.finish()                  // 负序号收尾包，触发服务端最终结果
            try? await Task.sleep(nanoseconds: 1_500_000_000)   // 给最后一轮 definite 分句留出往返时间
            cloud.cancel()
            cloudASR = nil
        } else if wasReconnecting {
            // 停在重连窗口里：whisper-server 压根没起来，别去调它（白跑一趟还污染卡死检测）；
            // 但最后一窗音频仍要进备份文件。
            flushToCloud()
        } else {
            inferQueue.sync { self.runInferenceSync(forceCommit: true, sessionElapsed: e) }   // final flush
        }
        server.stop()
        inferQueue.sync { self.backupAudioFile = nil }   // 显式关闭，落定 WAV 头，别等到下次录制才关
        return await MainActor.run { () -> String in
            self.isCapturing = false
            self.status = "已结束"
            self.liveText = self.committed
            self.pendingLine = ""          // 收尾后没有"还在成形"的句子了
            return self.committed.trimmingCharacters(in: .whitespaces)
        }
    }

    private func startTimers() {
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.isCapturing, !self.isPaused else { return }
            self.elapsed += 1
        }
        // 原始录音完全独立于云端/本地 ASR 的消费与成功状态。即使识别引擎卡死，音频仍持续落盘。
        backupFlushTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.isCapturing, !self.isPaused else { return }
            self.flushBackupAudio()
        }
        // 云端路径：每 200ms 把新到的音频转发出去（火山建议 100~200ms/包），服务端自己做分句
        // 重连期间也要继续跑以消费云端窗口；原始录音由独立 backupFlushTimer 负责。
        cloudSendTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, self.isCapturing, !self.isPaused, self.usingCloud || self.cloudReconnecting else { return }
            self.flushToCloud()
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: tickSeconds, repeats: true) { [weak self] _ in
            // 重连期间 whisper-server 并没起来，绝不能让本地推理在这时候空转（会误判成引擎卡死狂重启）
            guard let self, self.isCapturing, !self.isPaused, !self.usingCloud, !self.cloudReconnecting, !self.inferring else { return }
            self.inferring = true
            let e = self.elapsed                 // snapshot on main — runInferenceSync runs off-queue
            self.inferQueue.async {
                self.runInferenceSync(forceCommit: false, sessionElapsed: e)
                DispatchQueue.main.async { self.inferring = false }
            }
        }
    }

    /// Snapshot the accumulated window, mix, hand to the cloud session, trim what was sent —
    /// same snapshot/trim shape as runInferenceSync's local path, minus windowing/silence gating
    /// (the server does VAD-based segmentation itself).
    private func flushToCloud() {
        let (sysSnap, r, micSnap, mr) = audioQueue.sync { (self.window, self.rate, self.micWindow, self.micRate) }
        guard !sysSnap.isEmpty || !micSnap.isEmpty else { return }
        let mixed = Self.mix(sysSnap, r, micSnap, mr)
        audioQueue.async {
            if sysSnap.count <= self.window.count { self.window.removeFirst(sysSnap.count) } else { self.window.removeAll() }
            if micSnap.count <= self.micWindow.count { self.micWindow.removeFirst(micSnap.count) } else { self.micWindow.removeAll() }
        }
        cloudASR?.appendSamples(mixed)
        logLevelsPeriodically(sys: sysSnap, mic: micSnap, mixed: mixed)
    }

    /// 独立消费原始录音缓冲。它和 ASR 的 window/micWindow 完全分离，任何识别失败都不会阻止写盘。
    private func flushBackupAudio() {
        let (sysSnap, r, micSnap, mr) = audioQueue.sync {
            (self.backupWindow, self.rate, self.backupMicWindow, self.micRate)
        }
        guard !sysSnap.isEmpty || !micSnap.isEmpty else { return }
        let mixed = Self.mix(sysSnap, r, micSnap, mr)
        audioQueue.async {
            if sysSnap.count <= self.backupWindow.count { self.backupWindow.removeFirst(sysSnap.count) }
            else { self.backupWindow.removeAll() }
            if micSnap.count <= self.backupMicWindow.count { self.backupMicWindow.removeFirst(micSnap.count) }
            else { self.backupMicWindow.removeAll() }
        }
        appendBackupAudio(mixed, rate: r)
    }

    /// 每 ~10 秒记一次三路电平。削顶率是关键指标：正常语音应接近 0，
    /// 长期几个百分点就说明音频已经失真到会拖垮识别。
    private var lastLevelLog = Date.distantPast
    private func logLevelsPeriodically(sys: [Float], mic: [Float], mixed: [Float]) {
        guard Date().timeIntervalSince(lastLevelLog) > 10 else { return }
        lastLevelLog = Date()
        func stat(_ a: [Float]) -> String {
            guard !a.isEmpty else { return "—" }
            var sum: Float = 0, clipped = 0
            for v in a { sum += v * v; if abs(v) >= 0.999 { clipped += 1 } }
            let rms = sqrt(sum / Float(a.count))
            return String(format: "rms=%.3f clip=%.1f%%", rms, Float(clipped) / Float(a.count) * 100)
        }
        dbg("[lvl] sys(\(stat(sys))) mic(\(stat(mic))) mixed(\(stat(mixed)))")
    }

    // MARK: - CloudASRSessionDelegate (main thread — dispatched by CloudASRSession)

    func cloudASR(_ session: CloudASRSession, didUpdate utterances: [CloudASRUtterance]) {
        guard session === cloudASR, usingCloud else { return }
        cloudRetryCount = 0   // 真收到识别结果 = 链路确实通了，之前的失败不再累计

        // 用服务端时间轴去重，不用数组下标：无论服务端是"全量累计"还是"只回当前句"，
        // 也不管它中途重新分句，endTime 单调推进这一点始终成立。
        // （下标游标法曾导致提交完第一句后永久静默：列表长度不再增长，循环条件永远不成立。）
        for u in utterances where u.isDefinite && u.endTime > cloudLastCommittedEnd {
            cloudLastCommittedEnd = u.endTime
            let clean = collapseRepeats(u.text.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !clean.isEmpty else { continue }
            // 所有转写文件 I/O 都进 inferQueue；并快照 URL，避免自动续录后迟到任务写进下一场。
            if let url = sessionURL { inferQueue.async { self.appendToSession(clean, at: url) } }
            committed += (committed.isEmpty ? "" : " ") + clean
            appendLiveLine(clean)
        }

        // 尚未定稿的那句（还会被服务端改写）单独展示，不落盘
        let tail = utterances.last.flatMap { $0.isDefinite ? nil : $0.text } ?? ""
        pendingLine = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        liveText = tail.isEmpty ? committed : committed + (committed.isEmpty ? "" : " ") + tail
    }

    /// 追加一条已定稿分句到实时预览列表，并裁掉过老的（预览不需要全量，全量在 committed/文件里）
    private func appendLiveLine(_ line: String) {
        liveLines.append(line)
        if liveLines.count > Self.maxLiveLines {
            liveLines.removeFirst(liveLines.count - Self.maxLiveLines)
        }
    }

    func cloudASR(_ session: CloudASRSession, didFailWith error: Error) {
        guard session === cloudASR else { return }   // 旧会话的迟到回调，忽略
        cloudASR?.cancel(); cloudASR = nil
        handleCloudFailure(reason: (error as NSError).localizedDescription)
    }

    // MARK: - Inference (inferQueue, blocking allowed)

    private func runInferenceSync(forceCommit: Bool, sessionElapsed: Int) {
        let (sysSnap, r, micSnap, mr) = audioQueue.sync { (self.window, self.rate, self.micWindow, self.micRate) }
        let snap = Self.mix(sysSnap, r, micSnap, mr)   // 系统音频 + 麦克风 → 单路混音
        guard snap.count >= Int(1.0 * r) else { return }

        let tailN = min(snap.count, Int(0.6 * r))
        let tailEnergy = snap.suffix(tailN).reduce(Float(0)) { $0 + abs($1) } / Float(max(tailN, 1))
        let silentTail = tailEnergy < 0.01 && Double(snap.count) >= 1.5 * r
        let shouldCommit = forceCommit || silentTail || Double(snap.count) >= commitSeconds * r
        guard shouldCommit else { return }   // transcribe ONLY at a boundary → ~6× fewer server calls

        let trim = {
            self.audioQueue.async {
                if sysSnap.count <= self.window.count { self.window.removeFirst(sysSnap.count) } else { self.window.removeAll() }
                if micSnap.count <= self.micWindow.count { self.micWindow.removeFirst(micSnap.count) } else { self.micWindow.removeAll() }
            }
        }

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
        if let url = sessionURL { appendToSession(clean, at: url) } // persist this segment to disk immediately
        DispatchQueue.main.async {
            self.committed += (self.committed.isEmpty ? "" : " ") + clean
            self.liveText = self.committed
            self.appendLiveLine(clean)     // 本地路径没有"正在成形"的中间态，落一句算一句
        }
        trim()
    }

    /// 记一次实际音频格式（系统/麦克风各一次，变了再记）——排查"按 float32 误读"用
    private var loggedFormats: Set<String> = []
    private func logAudioFormatIfNeeded(_ asbd: AudioStreamBasicDescription, isMic: Bool) {
        let f = asbd.mFormatFlags
        let key = "\(isMic)|\(asbd.mSampleRate)|\(asbd.mChannelsPerFrame)|\(asbd.mBitsPerChannel)|\(f)"
        guard !loggedFormats.contains(key) else { return }
        loggedFormats.insert(key)
        let isFloat = (f & kAudioFormatFlagIsFloat) != 0
        let isInterleaved = (f & kAudioFormatFlagIsNonInterleaved) == 0
        dbg(String(format: "[fmt] %@ rate=%.0f ch=%d bits=%d float=%@ interleaved=%@",
                   isMic ? "mic" : "sys", asbd.mSampleRate, asbd.mChannelsPerFrame, asbd.mBitsPerChannel,
                   isFloat ? "Y" : "N", isInterleaved ? "Y" : "N"))
    }

    /// 两路混音：采样率不同先线性重采样对齐，再逐样本相加并限幅。
    /// 两路各自独立累积、每次消费后同时清空，漂移被窗口边界重置，ASR 足够。
    private static func mix(_ sys: [Float], _ sysRate: Double, _ mic: [Float], _ micRate: Double) -> [Float] {
        if mic.isEmpty { return sys }
        var m = mic
        if abs(sysRate - micRate) > 1, micRate > 0 {
            let ratio = micRate / sysRate
            let n = max(1, Int(Double(mic.count) / ratio))
            m = (0..<n).map { i in
                let x = Double(i) * ratio
                let j = Int(x)
                let s0 = mic[min(j, mic.count - 1)]
                let s1 = mic[min(j + 1, mic.count - 1)]
                return s0 + (s1 - s0) * Float(x - Double(j))
            }
        }
        if sys.isEmpty { return m }
        // 关键：两路各留 6dB 余量再相加，绝不裸加后硬削。
        // 之前是 sys+mic 直接夹到 ±1 —— 蓝牙耳机的麦克风带强 AGC，本身就贴近满幅，
        // 一相加就长期削顶（实测 24%~30% 的样本被削平，rms 高达 0.55，近乎方波）。
        // whisper 对这种失真还扛得住，云端识别基本就废了。
        var out = [Float](repeating: 0, count: max(sys.count, m.count))
        for i in out.indices {
            let a = i < sys.count ? sys[i] : 0
            let b = i < m.count ? m[i] : 0
            out[i] = softLimit(a * 0.5 + b * 0.5)
        }
        return out
    }

    /// 软限幅：0.8 以下保持线性（不动正常电平），超出部分平滑压缩到 ±1，
    /// 避免硬削产生的方波谐波——那正是识别引擎最难受的失真。
    private static func softLimit(_ x: Float) -> Float {
        let knee: Float = 0.8
        let a = abs(x)
        guard a > knee else { return x }
        let over = (a - knee) / (1 - knee)
        let shaped = knee + (1 - knee) * tanh(over)
        return x < 0 ? -shaped : shaped
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
        var isMic = false
        if #available(macOS 15.0, *), type == .microphone { isMic = true }
        guard (type == .audio || isMic), sb.isValid,
              let asbd = sb.formatDescription?.audioStreamBasicDescription,
              let fmt = AVAudioFormat(standardFormatWithSampleRate: asbd.mSampleRate, channels: asbd.mChannelsPerFrame)
        else { return }
        if isMic { micRate = asbd.mSampleRate } else { rate = asbd.mSampleRate }
        if pausedFlag { return }        // 暂停：采集流照跑，但音频一律丢弃（不入窗、不落盘）
        // standardFormat 强制按 float32/非交错解读；SCK 若换了格式（蓝牙切换时会重协商），
        // 硬按 float32 解字节就会读出 1e38、NaN 这类垃圾值。记一次真实格式，便于对账。
        logAudioFormatIfNeeded(asbd, isMic: isMic)
        try? sb.withAudioBufferList { abl, _ in
            guard let pcm = AVAudioPCMBuffer(pcmFormat: fmt, bufferListNoCopy: abl.unsafePointer),
                  let ch = pcm.floatChannelData else { return }
            let raw = UnsafeBufferPointer(start: ch[0], count: Int(pcm.frameLength))
            // 消毒：NaN/Inf 直接丢成静音，越界值夹紧。不做的话 NaN 在后面被 min/max 夹成 ±1，
            // 变成满幅爆音喂给识别引擎。
            let samples = raw.map { s -> Float in
                guard s.isFinite else { return 0 }
                return max(-1, min(1, s))
            }
            if isMic {
                self.micWindow.append(contentsOf: samples)
                self.backupMicWindow.append(contentsOf: samples)
            } else {
                self.window.append(contentsOf: samples)
                self.backupWindow.append(contentsOf: samples)
            }
        }
        // hard cap — drop oldest audio so the window (and inference cost) can't run away
        let maxN = Int(maxWindowSeconds * rate)
        if window.count > maxN { window.removeFirst(window.count - maxN) }
        let maxM = Int(maxWindowSeconds * micRate)
        if micWindow.count > maxM { micWindow.removeFirst(micWindow.count - maxM) }
        // 备份 timer 正常每 0.5s 消费；cap 只防主线程长时间卡死时内存无限增长。
        if backupWindow.count > maxN { backupWindow.removeFirst(backupWindow.count - maxN) }
        if backupMicWindow.count > maxM { backupMicWindow.removeFirst(backupMicWindow.count - maxM) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            self.tickTimer?.invalidate(); self.tickTimer = nil
            self.clockTimer?.invalidate(); self.clockTimer = nil
            self.backupFlushTimer?.invalidate(); self.backupFlushTimer = nil
            self.cloudSendTimer?.invalidate(); self.cloudSendTimer = nil
            self.cloudRetryWork?.cancel(); self.cloudRetryWork = nil
            let wasReconnecting = self.cloudReconnecting
            self.cloudReconnecting = false
            let e = self.elapsed
            self.status = "采集中断：\(error.localizedDescription)"
            self.isCapturing = false
            self.stream = nil
            self.flushBackupAudio()
            if self.usingCloud, let cloud = self.cloudASR {
                self.flushToCloud()
                cloud.finish()
                self.cloudASR = nil
                self.server.stop()
                self.inferQueue.async { self.backupAudioFile = nil }
            } else if wasReconnecting {
                self.flushToCloud()          // 同 stop()：重连窗口里本地引擎没起来，只收口备份音频
                self.server.stop()
                self.inferQueue.async { self.backupAudioFile = nil }
            } else {
                // 收口：把最后一窗音频落定，再关掉常驻 whisper-server（不然 ~1GB 常驻到下次录制）
                self.inferQueue.async {
                    self.runInferenceSync(forceCommit: true, sessionElapsed: e)
                    self.server.stop()
                    self.backupAudioFile = nil
                }
            }
        }
    }
}
