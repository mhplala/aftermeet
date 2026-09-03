import Foundation
import Security
import zlib

/// One finalized or in-progress sentence from the cloud recognizer.
/// 带上服务端给的时间轴：客户端靠 endTime 去重，而不是靠数组下标——
/// 下标法假设"每次返回全量累计列表且分句不变"，这个假设一旦不成立（只回当前句、
/// 或服务端重新分句）游标就会永久卡死，后续一个字都提交不了。
struct CloudASRUtterance {
    let text: String
    let isDefinite: Bool
    let startTime: Int      // ms，相对本次会话
    let endTime: Int
}

protocol CloudASRSessionDelegate: AnyObject {
    /// `utterances` is the full ordered list seen so far this session (server sends "full" mode,
    /// i.e. cumulative). Caller diffs against what it already committed by index.
    func cloudASR(_ session: CloudASRSession, didUpdate utterances: [CloudASRUtterance])
    func cloudASR(_ session: CloudASRSession, didFailWith error: Error)
}

struct CloudASRError: LocalizedError {
    let message: String
    let isRetryable: Bool
    init(message: String, isRetryable: Bool = true) {
        self.message = message
        self.isRetryable = isRetryable
    }
    var errorDescription: String? { message }
}

enum CloudASRMode: String, CaseIterable {
    case direct
    case proxy
}

/// Volcengine 豆包语音识别大模型 2.0 双向流式（bigmodel_async）。
///
/// 国内用户可直连火山官方入口，API Key 只放 macOS Keychain；对外发布时仍可切回
/// AfterMeet 代理，由服务端持有火山密钥并做用量控制。
enum CloudASRConfig {
    static let modeKey = "cloudASRMode"
    static let directBaseURL = "https://openspeech.bytedance.com"
    static let directPath = "/api/v3/sauc/bigmodel_async"
    static let directResourceID = "volc.seedasr.sauc.duration"
    static let directAppIDKey = "cloudASRVolcAppID"

    /// 新版控制台只发一枚 X-Api-Key；旧版语音控制台则发 App ID + Access Token。
    /// App ID 不是秘密，放 UserDefaults；Key / Token 始终只进 Keychain。
    static var directAppID: String {
        UserDefaults.standard.string(forKey: directAppIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// 保留零配置代理作为兼容选项；旧版没有 mode 时仍按 proxy 运行，不会在升级后突然丢掉云端转写。
    static let defaultBaseURL = "https://aftermeet-asr-proxy-production.mhplala.workers.dev"

    static var mode: CloudASRMode {
        CloudASRMode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "proxy") ?? .proxy
    }

    /// Explicit opt-out — default on (key absent = enabled) so emptying the address field below
    /// can't silently re-enable a stale/wrong override; this is the one true "off" switch.
    static var isEnabled: Bool {
        let d = UserDefaults.standard
        return d.object(forKey: "cloudASREnabled") == nil ? true : d.bool(forKey: "cloudASREnabled")
    }

    /// 断线时死磕云端、永不退回本地（默认关：退避重连若干次后才切本地）。
    /// 打开适合"宁可短暂缺一段，也要全程云端质量"的场景。
    static var neverFallbackToLocal: Bool {
        UserDefaults.standard.bool(forKey: "cloudASRNeverFallback")
    }

    /// 官方直连失败通常是当前网络不可用，快速切本地避免会议开头空白；
    /// 代理链路较长，保留原来的宽松重试窗口。
    static var maxReconnectAttempts: Int { mode == .direct ? 2 : 5 }

    static var proxyBaseURL: String {
        let v = (UserDefaults.standard.string(forKey: "cloudASRBaseURL") ?? "").trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? defaultBaseURL : v
    }
    static var isConfigured: Bool {
        guard isEnabled else { return false }
        switch mode {
        case .direct: return directAPIKey?.isEmpty == false
        case .proxy: return !proxyBaseURL.isEmpty
        }
    }

    static var webSocketURL: URL? {
        switch mode {
        case .direct:
            guard var c = URLComponents(string: directBaseURL) else { return nil }
            c.scheme = "wss"
            c.path = directPath
            return c.url
        case .proxy:
            guard !proxyBaseURL.isEmpty, var c = URLComponents(string: proxyBaseURL) else { return nil }
            c.scheme = (c.scheme == "http") ? "ws" : "wss"
            c.path = "/v1/transcribe-stream"
            c.query = nil
            return c.url
        }
    }

    static func authorize(_ request: inout URLRequest) throws {
        switch mode {
        case .direct:
            guard let key = directAPIKey, !key.isEmpty else {
                throw CloudASRError(message: "请先在设置中保存火山引擎 API Key / Access Token",
                                    isRetryable: false)
            }
            let requestID = UUID().uuidString.lowercased()
            if directAppID.isEmpty {
                request.setValue(key, forHTTPHeaderField: "X-Api-Key")
            } else {
                request.setValue(directAppID, forHTTPHeaderField: "X-Api-App-Key")
                request.setValue(key, forHTTPHeaderField: "X-Api-Access-Key")
            }
            request.setValue(directResourceID, forHTTPHeaderField: "X-Api-Resource-Id")
            request.setValue(requestID, forHTTPHeaderField: "X-Api-Request-Id")
            request.setValue(requestID, forHTTPHeaderField: "X-Api-Connect-Id")
        case .proxy:
            request.setValue("Bearer \(SikuCloud.deviceToken)", forHTTPHeaderField: "Authorization")
            request.setValue(SikuCloud.appSecret, forHTTPHeaderField: "X-Siku-App")
        }
    }

    // MARK: - Keychain

    private static let keychainService = "app.siku.aftermeet"
    private static let keychainAccount = "volcengine-asr-api-key"

    static var directAPIKey: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func setDirectAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        if trimmed.isEmpty {
            let status = SecItemDelete(base as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }

        let value = Data(trimmed.utf8)
        let updateStatus = SecItemUpdate(base as CFDictionary,
                                         [kSecValueData as String: value] as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var add = base
        add[kSecValueData as String] = value
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

/// One streaming recognition session = one meeting. Feed it continuous 16kHz mono Float32
/// samples as they're captured; it packetizes, gzips, and frames them per Volcengine's binary
/// protocol, and reports back the growing utterance list via delegate.
final class CloudASRSession: NSObject, URLSessionWebSocketDelegate {
    private enum Proto {
        static let version: UInt8 = 0x1
        static let headerSize: UInt8 = 0x1
        static let fullClientRequest: UInt8 = 0x1
        static let audioOnlyClientRequest: UInt8 = 0x2
        static let fullServerResponse: UInt8 = 0x9
        static let serverAck: UInt8 = 0xB
        static let serverError: UInt8 = 0xF
        static let positiveSequence: UInt8 = 0x1
        static let lastAudioPacket: UInt8 = 0x2
        static let noSerialization: UInt8 = 0x0
        static let jsonSerialization: UInt8 = 0x1
        static let noCompression: UInt8 = 0x0
        static let gzipCompression: UInt8 = 0x1
    }

    private static let recommendedPacketByteCount = 6_400   // ~200ms @16kHz mono int16
    /// 服务端在健康连接下几乎每个音频包都会有响应；这么久收不到任何响应，判定连接假死——
    /// 见过一次真实故障：WebSocket 被网络悄悄掐断，既没触发 didCloseWith 也没让 send 报错，
    /// 应用侧毫无感知地"录制中"了快 20 分钟，一个字都没转出来。没有这个看门狗就永远发现不了。
    ///
    /// 阈值必须放得很宽：bigmodel_async 是"只有识别结果有变化才回包"，全场安静时服务端本来就
    /// 一声不吭——会议里冷场两分钟完全正常。之前设 20s 会把健康连接误杀（真发生过）。
    /// 误判的代价现在也小了：触发的是重连，不是永久退回本地。
    private static let watchdogTimeout: TimeInterval = 120
    private static let watchdogInterval: TimeInterval = 10

    weak var delegate: CloudASRSessionDelegate?

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private let sendQueue = DispatchQueue(label: "aftermeet.cloudasr.send")
    private var pendingPCM16 = Data()
    private var nextAudioSequence: Int32 = 2
    private var isFinishing = false
    private var isCancelled = false
    private var didReportFailure = false
    private let failureLock = NSLock()
    private var utterances: [CloudASRUtterance] = []
    private var lastReceivedAt = Date()          // sendQueue-confined
    private var watchdogTimer: DispatchSourceTimer?

    // 诊断日志——之前这条链路完全黑盒，出问题只有一行含糊的 error，追不到到底卡在哪一步。
    // 写去和 CaptureService 同一个文件，同一次录制的时间线能对上。
    private static let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("aftermeet-capture.log")
    private static let logStamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()
    /// 每条会话只记一次返回形状（parseServerPacket 是 static，故这里也用 static，open() 时复位）
    private static var loggedShape = false
    private static func dbg(_ s: String) {
        guard let d = ("[\(logStamp.string(from: Date())) cloudasr] " + s + "\n").data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(d); try? h.close() }
        else { try? d.write(to: logURL) }
    }

    func open() throws {
        guard let url = CloudASRConfig.webSocketURL else {
            throw CloudASRError(message: "云端转写未配置")
        }
        Self.loggedShape = false
        Self.dbg("open() url=\(url.absoluteString)")
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        try CloudASRConfig.authorize(&request)

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        Self.dbg("task.resume() called")
        receiveNextMessage()
        startWatchdog()

        let initial = try makeInitialRequestPacket()
        Self.dbg("enqueueing initial request packet, \(initial.count) bytes")
        enqueue(.data(initial))
    }

    /// 每 5 秒检查一次：超过 watchdogTimeout 没收到服务端任何响应就当连接死了，走失败路径——
    /// 交给 CaptureService 的 didFailWith 处理，和真实网络错误走同一条自动退回本地的兜底。
    private func startWatchdog() {
        sendQueue.async { self.lastReceivedAt = Date() }
        let timer = DispatchSource.makeTimerSource(queue: sendQueue)
        timer.schedule(deadline: .now() + Self.watchdogInterval, repeating: Self.watchdogInterval)
        timer.setEventHandler { [weak self] in
            guard let self, !self.isCancelled, !self.isFinishing else { return }
            let idle = Date().timeIntervalSince(self.lastReceivedAt)
            guard idle > Self.watchdogTimeout else { return }
            // 一次性信号：判死后立刻停表，否则会反复上报同一条死讯刷屏
            self.stopWatchdog()
            Self.dbg("watchdog fired: idle=\(Int(idle))s → 判定连接假死")
            self.reportFailure(CloudASRError(message: "云端转写连接假死（\(Int(idle))秒无响应）"))
        }
        timer.resume()
        watchdogTimer = timer
    }

    /// Append mixed mono samples at the ASR-required 16kHz. Caller (CaptureService) already
    /// mixes system + mic audio to this rate for the local-whisper path, so no resampling here.
    func appendSamples(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        var pcm16 = Data(capacity: samples.count * 2)
        for s in samples {
            let clamped = max(-1, min(1, s))
            let v = Int16(clamped * Float(Int16.max))
            withUnsafeBytes(of: v.littleEndian) { pcm16.append(contentsOf: $0) }
        }
        sendQueue.async {
            guard !self.isCancelled, !self.isFinishing else { return }
            self.pendingPCM16.append(pcm16)
            self.flushPendingPackets(includeTrailingPartial: false)
        }
    }

    /// Send the last audio packet (negative sequence) and let the server's final response arrive
    /// via the delegate; caller closes/discards the session shortly after.
    func finish() {
        sendQueue.async {
            guard !self.isCancelled, !self.isFinishing else { return }
            self.isFinishing = true
            self.flushPendingPackets(includeTrailingPartial: true)
            let finalSeq = -max(2, self.nextAudioSequence)
            let packet = Self.makePacket(messageType: Proto.audioOnlyClientRequest,
                                          flags: Proto.positiveSequence | Proto.lastAudioPacket,
                                          serialization: Proto.noSerialization,
                                          compression: Proto.noCompression,
                                          sequence: finalSeq, payload: Data())
            self.enqueueLocked(.data(packet))
        }
    }

    func cancel() {
        sendQueue.async {
            self.isCancelled = true
            self.pendingPCM16.removeAll()
        }
        stopWatchdog()          // 不取消的话，被丢弃会话的定时器会一直空转报"假死"（见过跑了 3.8 天的）
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session = nil
    }

    private func stopWatchdog() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
    }

    // MARK: - Framing

    private func makeInitialRequestPacket() throws -> Data {
        let payloadObject: [String: Any] = [
            "user": ["uid": "aftermeet"],
            "audio": ["format": "pcm", "codec": "raw", "rate": 16_000, "bits": 16, "channel": 1],
            "request": [
                "model_name": "bigmodel",
                "enable_itn": true,
                "enable_punc": true,
                "enable_ddc": true,
                "show_utterances": true,
                "enable_nonstream": true,
                // 刻意不传 end_window_size：文档明确"配置该值就不使用语义分句，改按静音时长切"。
                // 之前传 700ms 导致句子被从中间劈开（说话人中途停顿就切，真正句尾反而不停）。
                // 交给服务端语义分句，读起来才是完整句子；代价是定稿稍慢，但 pendingLine
                // 已经把未定稿内容实时显示出来了，观感上不影响。
                "vad_segment_duration": 3000,
            ],
        ]
        let raw = try JSONSerialization.data(withJSONObject: payloadObject)
        let gzipped = try Self.gzip(raw)
        return Self.makePacket(messageType: Proto.fullClientRequest, flags: Proto.positiveSequence,
                                serialization: Proto.jsonSerialization, compression: Proto.gzipCompression,
                                sequence: 1, payload: gzipped)
    }

    private func flushPendingPackets(includeTrailingPartial: Bool) {
        while pendingPCM16.count >= Self.recommendedPacketByteCount
            || (includeTrailingPartial && !pendingPCM16.isEmpty) {
            let n = min(pendingPCM16.count, Self.recommendedPacketByteCount)
            let chunk = Data(pendingPCM16.prefix(n))
            pendingPCM16.removeSubrange(0..<n)
            sendAudioPacket(chunk)
        }
    }

    private func sendAudioPacket(_ pcm16: Data) {
        guard !pcm16.isEmpty else { return }
        do {
            let gzipped = try Self.gzip(pcm16)
            let packet = Self.makePacket(messageType: Proto.audioOnlyClientRequest, flags: Proto.positiveSequence,
                                          serialization: Proto.noSerialization, compression: Proto.gzipCompression,
                                          sequence: nextAudioSequence, payload: gzipped)
            nextAudioSequence += 1
            enqueueLocked(.data(packet))
        } catch {
            reportFailure(error)
        }
    }

    private func enqueue(_ message: URLSessionWebSocketTask.Message) {
        sendQueue.async { self.enqueueLocked(message) }
    }

    private var hasLoggedFirstSend = false

    private func enqueueLocked(_ message: URLSessionWebSocketTask.Message) {
        guard let task else {
            Self.dbg("enqueueLocked: no task, dropping message")
            return
        }
        task.send(message) { [weak self] error in
            guard let self else { return }
            if let error {
                let ns = error as NSError
                Self.dbg("send FAILED: domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription)")
                self.reportFailure(self.connectionFailure(from: error))
                return
            }
            if !self.hasLoggedFirstSend {
                self.hasLoggedFirstSend = true
                Self.dbg("first send completed OK")
            }
        }
    }

    // MARK: - Receiving

    private var hasLoggedFirstReceive = false

    private func receiveNextMessage() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.sendQueue.async { self.lastReceivedAt = Date() }   // 喂看门狗——这行漏了是真实故障的根因
                if !self.hasLoggedFirstReceive {
                    self.hasLoggedFirstReceive = true
                    Self.dbg("first receive OK")
                }
                if case .data(let data) = message { self.handleIncoming(data) }
                self.receiveNextMessage()
            case .failure(let error):
                let ns = error as NSError
                Self.dbg("receive FAILED: domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription)")
                if !self.isCancelled { self.reportFailure(self.connectionFailure(from: error)) }
            }
        }
    }

    /// Foundation otherwise collapses every failed WebSocket upgrade into the unhelpful -1011.
    /// Preserve the HTTP status and Volcengine log id, and mark auth/entitlement failures permanent
    /// so CaptureService does not retry the exact same rejected credentials forever.
    private func connectionFailure(from underlying: Error) -> Error {
        guard let response = task?.response as? HTTPURLResponse else { return underlying }
        let status = response.statusCode
        let logID = response.value(forHTTPHeaderField: "X-Tt-Logid")
        let suffix = logID.map { " · Log ID \($0)" } ?? ""
        let detail: String
        switch status {
        case 401:
            detail = "鉴权失败：请检查 API Key，或填写 App ID + Access Token"
        case 403:
            detail = "资源未授权：请确认语音识别 2.0 已开通且资源 ID 匹配"
        case 429:
            detail = "请求过多或额度已用尽"
        default:
            detail = "WebSocket 握手失败"
        }
        let retryable = status == 408 || status == 429 || status >= 500
        Self.dbg("handshake HTTP \(status)\(suffix)")
        return CloudASRError(message: "云端转写 \(detail)（HTTP \(status)）\(suffix)",
                             isRetryable: retryable)
    }

    private func handleIncoming(_ packet: Data) {
        do {
            guard let parsed = try Self.parseServerPacket(packet) else { return }
            if !parsed.isEmpty {
                utterances = parsed
                DispatchQueue.main.async { self.delegate?.cloudASR(self, didUpdate: self.utterances) }
            }
        } catch {
            reportFailure(error)
        }
    }

    private func reportFailure(_ error: Error) {
        guard !isCancelled else { return }
        failureLock.lock()
        guard !didReportFailure else { failureLock.unlock(); return }
        didReportFailure = true
        failureLock.unlock()
        Self.dbg("reportFailure: \((error as NSError).localizedDescription)")
        DispatchQueue.main.async { self.delegate?.cloudASR(self, didFailWith: error) }
    }

    // MARK: - Packet build/parse (Volcengine binary protocol — big-endian, 4-byte header)

    private static func makePacket(messageType: UInt8, flags: UInt8, serialization: UInt8,
                                    compression: UInt8, sequence: Int32, payload: Data) -> Data {
        var out = Data()
        out.append((version << 4) | headerSize)
        out.append((messageType << 4) | flags)
        out.append((serialization << 4) | compression)
        out.append(0x00)
        if (flags & positiveSequence) != 0 || (flags & lastAudioPacket) != 0 {
            appendBEInt32(sequence, to: &out)
        }
        appendBEUInt32(UInt32(payload.count), to: &out)
        out.append(payload)
        return out
    }
    private static let version = Proto.version
    private static let headerSize = Proto.headerSize
    private static let positiveSequence = Proto.positiveSequence
    private static let lastAudioPacket = Proto.lastAudioPacket

    private static func parseServerPacket(_ data: Data) throws -> [CloudASRUtterance]? {
        guard data.count >= 4 else { throw CloudASRError(message: "云端转写返回了不完整的数据") }
        let headerBytes = max(4, Int(data[0] & 0x0F) * 4)
        guard data.count >= headerBytes else { throw CloudASRError(message: "云端转写返回了无效协议头") }
        let messageType = (data[1] >> 4) & 0x0F
        let flags = data[1] & 0x0F
        let compression = data[2] & 0x0F
        var cursor = headerBytes

        if (flags & Proto.positiveSequence) != 0 || (flags & Proto.lastAudioPacket) != 0 { cursor += 4 }

        switch messageType {
        case Proto.fullServerResponse:
            let n = Int(try readBEUInt32(data, cursor)); cursor += 4
            let payload = try slice(data, cursor, n)
            let decoded = try decode(payload, compression: compression)
            guard !decoded.isEmpty,
                  let obj = try JSONSerialization.jsonObject(with: decoded) as? [String: Any],
                  let result = obj["result"] as? [String: Any] else { return nil }
            guard let raw = result["utterances"] as? [[String: Any]] else {
                if let text = result["text"] as? String, !text.isEmpty {
                    return [CloudASRUtterance(text: text, isDefinite: false, startTime: 0, endTime: 0)]
                }
                return nil
            }
            let parsed = raw.map { u in
                CloudASRUtterance(text: (u["text"] as? String) ?? "",
                                  isDefinite: (u["definite"] as? Bool) ?? false,
                                  startTime: (u["start_time"] as? Int) ?? 0,
                                  endTime: (u["end_time"] as? Int) ?? 0)
            }
            // 一次性记下真实返回形状，供排查"到底是全量还是增量"
            if !loggedShape {
                loggedShape = true
                let def = parsed.filter(\.isDefinite).count
                dbg("首个 utterances 返回：count=\(parsed.count) definite=\(def) " +
                    "times=\(parsed.map { "\($0.startTime)-\($0.endTime)" }.joined(separator: ","))")
            }
            return parsed

        case Proto.serverError:
            let code = try readBEUInt32(data, cursor); cursor += 4
            let n = Int(try readBEUInt32(data, cursor)); cursor += 4
            let payload = try slice(data, cursor, n)
            let decoded = (try? decode(payload, compression: compression)) ?? payload
            let msg = String(data: decoded, encoding: .utf8) ?? "未知错误"
            throw CloudASRError(message: "云端转写失败（\(code)）：\(msg.prefix(200))")

        default:
            return nil
        }
    }

    private static func slice(_ data: Data, _ cursor: Int, _ n: Int) throws -> Data {
        guard n >= 0, cursor >= 0, cursor + n <= data.count else {
            throw CloudASRError(message: "云端转写返回了异常大小的数据")
        }
        return data.subdata(in: cursor..<(cursor + n))
    }

    private static func decode(_ payload: Data, compression: UInt8) throws -> Data {
        switch compression {
        case Proto.noCompression: return payload
        case Proto.gzipCompression: return try gunzip(payload)
        default: throw CloudASRError(message: "云端转写使用了不支持的压缩格式")
        }
    }

    private static func appendBEInt32(_ v: Int32, to data: inout Data) { appendBEUInt32(UInt32(bitPattern: v), to: &data) }
    private static func appendBEUInt32(_ v: UInt32, to data: inout Data) {
        data.append(UInt8((v >> 24) & 0xFF)); data.append(UInt8((v >> 16) & 0xFF))
        data.append(UInt8((v >> 8) & 0xFF)); data.append(UInt8(v & 0xFF))
    }
    private static func readBEUInt32(_ data: Data, _ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { throw CloudASRError(message: "云端转写返回了截断的数据") }
        return UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16
             | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
    }

    // MARK: - gzip (zlib, +16 window bits = gzip framing)

    private static func gzip(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        return try data.withUnsafeBytes { raw -> Data in
            guard let input = raw.bindMemory(to: UInt8.self).baseAddress else { return Data() }
            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer<Bytef>(OpaquePointer(input))
            stream.avail_in = uInt(data.count)
            guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, MAX_WBITS + 16, MAX_MEM_LEVEL,
                                 Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK
            else { throw CloudASRError(message: "无法压缩音频数据") }
            defer { deflateEnd(&stream) }

            var out = Data()
            var status: Int32 = Z_OK
            while status == Z_OK {
                var buf = [UInt8](repeating: 0, count: 16_384)
                let count = buf.count
                status = buf.withUnsafeMutableBytes { mb -> Int32 in
                    stream.next_out = UnsafeMutablePointer<Bytef>(mb.bindMemory(to: UInt8.self).baseAddress)
                    stream.avail_out = uInt(count)
                    return deflate(&stream, Z_FINISH)
                }
                let written = count - Int(stream.avail_out)
                if written > 0 { out.append(contentsOf: buf[0..<written]) }
            }
            guard status == Z_STREAM_END else { throw CloudASRError(message: "音频数据压缩失败") }
            return out
        }
    }

    private static func gunzip(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        return try data.withUnsafeBytes { raw -> Data in
            guard let input = raw.bindMemory(to: UInt8.self).baseAddress else { return Data() }
            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer<Bytef>(OpaquePointer(input))
            stream.avail_in = uInt(data.count)
            guard inflateInit2_(&stream, MAX_WBITS + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK
            else { throw CloudASRError(message: "无法解压识别结果") }
            defer { inflateEnd(&stream) }

            var out = Data()
            var status: Int32 = Z_OK
            while status == Z_OK {
                var buf = [UInt8](repeating: 0, count: 16_384)
                let count = buf.count
                status = buf.withUnsafeMutableBytes { mb -> Int32 in
                    stream.next_out = UnsafeMutablePointer<Bytef>(mb.bindMemory(to: UInt8.self).baseAddress)
                    stream.avail_out = uInt(count)
                    return inflate(&stream, Z_SYNC_FLUSH)
                }
                let written = count - Int(stream.avail_out)
                if written > 0 { out.append(contentsOf: buf[0..<written]) }
                guard out.count <= 8 * 1024 * 1024 else { throw CloudASRError(message: "识别结果过大，已停止处理") }
                guard status == Z_OK || status == Z_STREAM_END else { throw CloudASRError(message: "识别结果解压失败") }
            }
            return out
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol proto: String?) {
        Self.dbg("didOpenWithProtocol: \(proto ?? "nil") — handshake completed")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let response = task.response as? HTTPURLResponse {
            let logID = response.value(forHTTPHeaderField: "X-Tt-Logid") ?? "-"
            Self.dbg("HTTP response status=\(response.statusCode) logid=\(logID)")
        }
        if let error {
            let ns = error as NSError
            Self.dbg("didCompleteWithError: domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "-"
        Self.dbg("didCloseWith code=\(closeCode.rawValue) reason=\(reasonText)")
        if !isCancelled, closeCode != .normalClosure, closeCode != .goingAway {
            reportFailure(CloudASRError(message: "云端转写连接意外断开（code \(closeCode.rawValue)）"))
        }
    }
}
