import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Whisper 模型下载器（hf-mirror 直连；内网被拦时诚实报错）

@MainActor
final class ModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var progress: [String: Double] = [:]     // 文件名 → 0…1
    @Published var errors: [String: String] = [:]
    private var names: [Int: String] = [:]               // taskIdentifier → 文件名

    /// 下载源按序回退：镜像失败自动换官方源，全挂才报错
    static let sources = [
        "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/",
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/",
    ]
    private var sourceIndex: [String: Int] = [:]         // 文件名 → 当前用第几个源

    static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AfterMeet/models")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30          // 停滞 30 秒就失败换源，别无限转圈
        cfg.timeoutIntervalForResource = 4 * 3600   // 慢网整体上限 4 小时
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    enum ImportResult { case imported(String), cancelled, failed(String) }

    /// 浏览器逃生门下载完的文件从「下载」导入模型目录。
    /// 浏览器走用户自己的代理/DoH，经常是内网环境里唯一通的路。
    static func importModelInteractively() -> ImportResult {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.allowedContentTypes = [UTType(filenameExtension: "bin")].compactMap { $0 }
        panel.message = "选择浏览器下载好的 ggml-*.bin 模型文件"
        guard panel.runModal() == .OK, let src = panel.url else { return .cancelled }
        let name = src.lastPathComponent
        guard name.hasPrefix("ggml-"), name.hasSuffix(".bin") else {
            return .failed("不是 whisper 模型文件（应为 ggml-*.bin）")
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: src.path)[.size] as? Int64) ?? 0
        guard size > 30_000_000 else {
            return .failed("文件不完整（\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))），可能没下载完")
        }
        let dest = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: src, to: dest)
            return .imported(name)
        } catch {
            return .failed("导入失败：\(error.localizedDescription)")
        }
    }

    func download(_ file: String) {
        guard progress[file] == nil else { return }
        sourceIndex[file] = 0
        startAttempt(file)
    }

    private func startAttempt(_ file: String) {
        let idx = sourceIndex[file] ?? 0
        guard idx < Self.sources.count, let url = URL(string: Self.sources[idx] + file) else { return }
        errors[file] = nil
        progress[file] = 0
        let task = session.downloadTask(with: url)
        names[task.taskIdentifier] = file
        task.resume()
    }

    /// 当前源失败 → 还有下一个源就静默换源重试；true = 已换源，不用报错
    private func advanceSource(_ file: String) -> Bool {
        let next = (sourceIndex[file] ?? 0) + 1
        guard next < Self.sources.count else { return false }
        sourceIndex[file] = next
        startAttempt(file)
        return true
    }

    // delegate（非主线程）→ 回主线程发布
    nonisolated func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let pct = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        let id = downloadTask.taskIdentifier
        Task { @MainActor in
            if let f = self.names[id] { self.progress[f] = pct }
        }
    }

    nonisolated func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        let id = downloadTask.taskIdentifier
        let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        // 目标路径要在这个（同步）回调里就搬走，location 出了作用域即失效
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.moveItem(at: location, to: tmp)
        Task { @MainActor in
            guard let f = self.names[id] else { return }
            defer { self.names[id] = nil }
            guard code == 200 else {
                try? FileManager.default.removeItem(at: tmp)
                if self.advanceSource(f) { return }        // 换下一个源重试
                self.progress[f] = nil
                self.errors[f] = "下载失败（HTTP \(code)，已尝试全部下载源）"
                return
            }
            let dest = Self.dir.appendingPathComponent(f)
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.moveItem(at: tmp, to: dest)
                self.progress[f] = nil
            } catch {
                self.progress[f] = nil
                self.errors[f] = "保存失败：\(error.localizedDescription)"
            }
        }
    }

    nonisolated func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let id = task.taskIdentifier
        Task { @MainActor in
            if let f = self.names[id] {
                self.names[id] = nil
                if self.advanceSource(f) { return }        // 换下一个源重试
                self.progress[f] = nil
                self.errors[f] = "网络错误：\(error.localizedDescription)"
            }
        }
    }
}

// MARK: - 设置页

struct SettingsScreen: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var downloader = ModelDownloader()
    @State private var currentModel = Whisper.model
    @State private var cloudASRMode = CloudASRConfig.mode.rawValue
    @State private var cloudASRURL = UserDefaults.standard.string(forKey: "cloudASRBaseURL") ?? ""
    @State private var cloudASREnabled = CloudASRConfig.isEnabled
    @State private var cloudNeverFallback = CloudASRConfig.neverFallbackToLocal
    @State private var volcASRAppID = CloudASRConfig.directAppID
    @State private var volcASRKey = CloudASRConfig.directAPIKey ?? ""
    @State private var volcASRKeySaved = CloudASRConfig.directAPIKey?.isEmpty == false
    @State private var volcASRKeySaveFailed = false
    @State private var micMode = AudioInputDevices.mode
    @State private var inputDevices: [AudioInputDevice] = []
    @State private var localModels: [(path: String, size: String)] = []
    @State private var showAdvanced = false

    // BYOK 表单状态
    @State private var aiMode = UserDefaults.standard.string(forKey: AIBackend.modeKey) ?? "builtin"
    @State private var byokURL = UserDefaults.standard.string(forKey: AIBackend.urlKey) ?? ""
    @State private var byokModel = UserDefaults.standard.string(forKey: AIBackend.modelKey) ?? ""
    @State private var byokKey = AIBackend.apiKey ?? ""
    @State private var testingAI = false

    /// 可下载的常用模型（多语种，中文可用；q5 为量化版，体积小速度快）
    private let downloadable: [(file: String, label: String, size: String)] = [
        ("ggml-small.bin",             "Small · 快，精度一般",        "466 MB"),
        ("ggml-medium-q5_0.bin",       "Medium Q5 · 推荐，中文较准",  "514 MB"),
        ("ggml-large-v3-turbo-q5_0.bin", "Large v3 Turbo Q5 · 最准", "547 MB"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("设置")
                    .font(Theme.display(36, .semibold)).tracking(-0.8)
                    .foregroundColor(Theme.inkPrimary)
                    .padding(.bottom, 20)

                section("转写") { transcriptionSummary }
                section("录制") { recordSection }
                section("AI 服务") { aiSection }
                advancedSettings
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
        .onAppear { scanModels(); inputDevices = AudioInputDevices.list() }
    }

    private var transcriptionSummary: some View {
        row {
            Toggle("", isOn: $cloudASREnabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .onChange(of: cloudASREnabled) { _, v in UserDefaults.standard.set(v, forKey: "cloudASREnabled") }
            VStack(alignment: .leading, spacing: 2) {
                Text(cloudASREnabled ? (cloudASRMode == CloudASRMode.direct.rawValue ? "火山直连" : "AfterMeet 代理")
                                     : "本地转写")
                    .font(Theme.ui(13, .medium)).foregroundColor(Theme.inkPrimary)
                Text(cloudASREnabled
                     ? (CloudASRConfig.isConfigured ? "已配置" : "需要在高级设置中完成配置")
                     : "音频不出网，使用本地 whisper")
                    .font(Theme.mono(9.5))
                    .foregroundColor(CloudASRConfig.isConfigured || !cloudASREnabled ? Theme.inkMuted : Theme.warn500)
            }
            Spacer()
            Circle().fill(CloudASRConfig.isConfigured || !cloudASREnabled ? Theme.green500 : Theme.warn500)
                .frame(width: 7, height: 7)
        }
    }

    private var advancedSettings: some View {
        Card(padding: 0) {
            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 12) {
                    advancedLabel("转写连接")
                    engineSection
                    advancedLabel("本地模型")
                    modelSection
                    advancedLabel("飞书连接")
                    larkSection
                    advancedLabel("数据")
                    dataSection
                }
                .padding(.top, 14)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13)).foregroundColor(Theme.inkSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("高级设置").font(Theme.ui(13, .medium)).foregroundColor(Theme.inkPrimary)
                        Text("接入密钥、本地模型与诊断")
                            .font(Theme.mono(9.5)).foregroundColor(Theme.inkMuted)
                    }
                }
            }
            .tint(Theme.inkSecondary)
            .padding(16)
        }
        .padding(.bottom, 22)
    }

    private func advancedLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(10, .semibold)).tracking(0.8)
            .foregroundColor(Theme.inkMuted)
            .padding(.top, 6)
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: @escaping () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.mono(10.5, .semibold)).tracking(1.0).textCase(.uppercase)
                .foregroundColor(Theme.inkMuted)
            Card(padding: 0) { content() }
        }
        .padding(.bottom, 22)
    }

    // MARK: 转写引擎

    private var engineSection: some View {
        let server = ToolPath.resolve("whisper-server")
        let bundled = server?.hasPrefix(Bundle.main.bundlePath) == true
        return VStack(spacing: 0) {
            row {
                Text("接入方式").font(Theme.ui(12.5)).foregroundColor(Theme.inkSecondary)
                Spacer()
                Picker("", selection: $cloudASRMode) {
                    Text("火山直连（国内推荐）").tag(CloudASRMode.direct.rawValue)
                    Text("AfterMeet 代理").tag(CloudASRMode.proxy.rawValue)
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 300)
                .onChange(of: cloudASRMode) { _, v in
                    UserDefaults.standard.set(v, forKey: CloudASRConfig.modeKey)
                }
            }
            if cloudASRMode == CloudASRMode.direct.rawValue {
                Hairline()
                row {
                    Text("App ID").font(Theme.ui(12.5)).foregroundColor(Theme.inkSecondary).frame(width: 76, alignment: .leading)
                    TextField("新版单 Key 模式可留空", text: $volcASRAppID)
                        .textFieldStyle(.plain).font(Theme.mono(12)).foregroundColor(Theme.inkPrimary)
                        .autocorrectionDisabled()
                        .onChange(of: volcASRAppID) { _, v in
                            UserDefaults.standard.set(v.trimmingCharacters(in: .whitespacesAndNewlines),
                                                      forKey: CloudASRConfig.directAppIDKey)
                        }
                    Spacer()
                    Text("旧版控制台必填").font(Theme.mono(9.5)).foregroundColor(Theme.inkMuted)
                }
                Hairline()
                row {
                    Text("密钥").font(Theme.ui(12.5)).foregroundColor(Theme.inkSecondary).frame(width: 76, alignment: .leading)
                    SecureField("API Key 或 Access Token", text: $volcASRKey)
                        .textFieldStyle(.plain).font(Theme.mono(12)).foregroundColor(Theme.inkPrimary)
                        .onChange(of: volcASRKey) { _, _ in
                            volcASRKeySaved = false
                            volcASRKeySaveFailed = false
                        }
                    Spacer()
                    if volcASRKeySaveFailed {
                        Text("钥匙串写入失败").font(Theme.mono(9.5)).foregroundColor(Theme.danger500)
                    } else if volcASRKeySaved {
                        Text("已存钥匙串").font(Theme.mono(9.5)).foregroundColor(Theme.green500)
                    }
                    Button {
                        let ok = CloudASRConfig.setDirectAPIKey(volcASRKey)
                        volcASRKeySaved = ok && !volcASRKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        volcASRKeySaveFailed = !ok
                    } label: {
                        Text("保存").font(Theme.ui(11.5, .semibold)).foregroundColor(Theme.inkSecondary)
                            .padding(.horizontal, 11).padding(.vertical, 5)
                            .background(Theme.white).clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(Theme.borderDefault, lineWidth: 1))
                            .contentShape(Capsule())
                    }.buttonStyle(.plain)
                }
                Text("火山语音控制台若显示 App ID + Access Token，请两项都填；若只提供 X-Api-Key，App ID 留空。")
                    .font(Theme.mono(9.5)).foregroundColor(Theme.inkMuted)
                    .padding(.horizontal, 16).padding(.vertical, 8)
            } else {
                Hairline()
                row {
                    Text("代理地址").font(Theme.ui(12.5)).foregroundColor(Theme.inkSecondary).frame(width: 76, alignment: .leading)
                    TextField(CloudASRConfig.defaultBaseURL, text: $cloudASRURL)
                        .textFieldStyle(.plain).font(Theme.mono(12)).foregroundColor(Theme.inkPrimary)
                        .autocorrectionDisabled()
                        .onChange(of: cloudASRURL) { _, v in
                            UserDefaults.standard.set(v.trimmingCharacters(in: .whitespaces), forKey: "cloudASRBaseURL")
                        }
                    Spacer()
                    Text("留空 = 用内置地址").font(Theme.mono(9.5)).foregroundColor(Theme.inkMuted)
                }
            }
            Hairline()
            row {
                Toggle("", isOn: $cloudNeverFallback).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .onChange(of: cloudNeverFallback) { _, v in UserDefaults.standard.set(v, forKey: "cloudASRNeverFallback") }
                    .disabled(!cloudASREnabled)
                VStack(alignment: .leading, spacing: 2) {
                    Text("断线时死磕云端，不退回本地").font(Theme.ui(13)).foregroundColor(cloudASREnabled ? Theme.inkPrimary : Theme.inkMuted)
                    Text(cloudNeverFallback ? "一直退避重连直到恢复；重连期间音频照常录，但这段会缺字"
                                            : (cloudASRMode == CloudASRMode.direct.rawValue
                                               ? "直连重试 2 次仍失败即切本地 whisper（约 3 秒）"
                                               : "代理重试 5 次仍失败才切本地 whisper（约 30 秒）"))
                        .font(Theme.mono(9.5)).foregroundColor(Theme.inkMuted)
                }
                Spacer()
            }
            Hairline()
            statusRow("本地 whisper-server（离线兜底）", ok: server != nil,
                      okText: bundled ? "内置" : (server ?? "已安装"),
                      failText: "未找到（重新安装应用，或 brew install whisper-cpp）")
        }
    }

    // MARK: 转写模型

    private var modelSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(localModels.enumerated()), id: \.element.path) { idx, m in
                let name = (m.path as NSString).lastPathComponent
                let on = m.path == currentModel
                Button {
                    currentModel = m.path
                    UserDefaults.standard.set(m.path, forKey: "whisperModel")
                    store.showToast("已切换模型，下次录制生效")
                } label: {
                    row {
                        Image(systemName: on ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 14)).foregroundColor(on ? Theme.blue500 : Theme.inkMuted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(Theme.ui(13, .medium)).foregroundColor(Theme.inkPrimary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                Hairline()
            }
            if localModels.isEmpty {
                row { Text("本机未找到模型文件").font(Theme.ui(13)).foregroundColor(Theme.inkTertiary); Spacer() }
                Hairline()
            }

            ForEach(downloadable, id: \.file) { d in
                if !localModels.contains(where: { ($0.path as NSString).lastPathComponent == d.file }) {
                    row {
                        Image(systemName: "arrow.down.circle").font(.system(size: 14)).foregroundColor(Theme.inkTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.label).font(Theme.ui(13)).foregroundColor(Theme.inkPrimary)
                            if let err = downloader.errors[d.file] {
                                Text(err).font(Theme.mono(9.5)).foregroundColor(Theme.danger500)
                            } else {
                                Text(d.file).font(Theme.mono(9.5)).foregroundColor(Theme.inkMuted)
                            }
                        }
                        Spacer()
                        if downloader.errors[d.file] != nil {
                            Button {
                                if let url = URL(string: "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/\(d.file)") {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Text("浏览器下载").font(Theme.ui(11.5, .semibold)).foregroundColor(Theme.inkSecondary)
                                    .padding(.horizontal, 11).padding(.vertical, 5)
                                    .background(Theme.white).clipShape(Capsule())
                                    .overlay(Capsule().strokeBorder(Theme.borderDefault, lineWidth: 1))
                                    .contentShape(Capsule())
                            }.buttonStyle(.plain)
                        }
                        if let p = downloader.progress[d.file] {
                            ProgressView(value: p).frame(width: 90)
                            Text("\(Int(p * 100))%").font(Theme.mono(10.5)).foregroundColor(Theme.inkTertiary)
                                .frame(width: 34, alignment: .trailing)
                        } else {
                            Text(d.size).font(Theme.mono(11)).foregroundColor(Theme.inkTertiary)
                            Button {
                                downloader.download(d.file)
                                pollDownload(d.file)
                            } label: {
                                Text("下载").font(Theme.ui(11.5, .semibold)).foregroundColor(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 5)
                                    .background(Theme.inkGrad).clipShape(Capsule())
                                    .contentShape(Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                    Hairline()
                }
            }

            row {
                Text("应用内下载不通时：浏览器下载后点「导入模型文件」即可")
                    .font(Theme.mono(10)).foregroundColor(Theme.inkMuted)
                Spacer()
                Button {
                    switch ModelDownloader.importModelInteractively() {
                    case .imported: scanModels(); store.showToast("模型已导入")
                    case .failed(let why): store.showToast(why)
                    case .cancelled: break
                    }
                } label: {
                    Text("导入模型文件…").font(Theme.ui(11.5, .semibold)).foregroundColor(Theme.inkSecondary)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(Theme.white).clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Theme.borderDefault, lineWidth: 1))
                        .contentShape(Capsule())
                }.buttonStyle(.plain)
                Button { NSWorkspace.shared.activateFileViewerSelecting([ModelDownloader.dir]) } label: {
                    Text("打开模型目录").font(Theme.ui(11.5, .semibold)).foregroundColor(Theme.inkSecondary)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(Theme.white).clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Theme.borderDefault, lineWidth: 1))
                        .contentShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
    }

    /// 下载完成后刷新本地列表（简单轮询，下载不频繁）
    private func pollDownload(_ file: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if downloader.progress[file] != nil { pollDownload(file) } else { scanModels() }
        }
    }

    // MARK: 录制

    private var recordSection: some View {
        VStack(spacing: 0) {
            row {
                Toggle("", isOn: Binding(get: { store.autoStart }, set: { store.setAutoStart($0) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("检测到会议自动开始记录").font(Theme.ui(13)).foregroundColor(Theme.inkPrimary)
                    Text("麦克风活跃且存在会议窗口时自动录制").font(Theme.mono(9.5)).foregroundColor(Theme.inkMuted)
                }
                Spacer()
            }
            Hairline()
            row {
                VStack(alignment: .leading, spacing: 2) {
                    Text("录音麦克风").font(Theme.ui(13)).foregroundColor(Theme.inkPrimary)
                    Text(micHint).font(Theme.mono(9.5)).foregroundColor(micWarns ? Theme.warn500 : Theme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Picker("", selection: $micMode) {
                    Text("自动（避开蓝牙）").tag("auto")
                    Text("跟随系统默认").tag("system")
                    ForEach(inputDevices) { d in
                        Text(d.name + (d.isBluetooth ? "（蓝牙）" : "")).tag(d.id)
                    }
                }
                .labelsHidden().frame(width: 210)
                .onChange(of: micMode) { _, v in UserDefaults.standard.set(v, forKey: AudioInputDevices.modeKey) }
            }
        }
    }

    /// 蓝牙耳机做麦克风会被 macOS 从 A2DP 拽到 HFP：音质掉到电话级，且 AGC 把电平顶到削顶，
    /// 直接拖垮识别。这里如实告诉用户当前选择会不会触发。
    private var micWarns: Bool { AudioInputDevices.willForceBluetoothHFP() }
    private var micHint: String {
        micWarns
            ? "当前会占用蓝牙耳机麦克风：耳机将切到 HFP，音质降为电话级且易削顶，建议改用内置麦克风"
            : "避免占用蓝牙耳机麦克风，耳机保持音乐音质（A2DP），你的声音走内置麦克风"
    }

    // MARK: 飞书

    private var larkSection: some View {
        statusRow("lark-cli", ok: Lark.available,
                  okText: Lark.available ? "已连接" : "已安装",
                  failText: "未连接")
    }

    // MARK: AI 服务（内置 / BYOK）

    private var aiSection: some View {
        VStack(spacing: 0) {
            row {
                Text("服务来源").font(Theme.ui(13)).foregroundColor(Theme.inkPrimary)
                Spacer()
                Picker("", selection: $aiMode) {
                    Text("内置").tag("builtin")
                    Text("自定义 API").tag("byok")
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                .onChange(of: aiMode) { _, v in
                    UserDefaults.standard.set(v, forKey: AIBackend.modeKey)
                }
            }
            if aiMode == "byok" {
                Hairline()
                byokForm
            }
        }
    }

    private var byokForm: some View {
        VStack(spacing: 0) {
            row {
                Text("Base URL").font(Theme.ui(12.5)).foregroundColor(Theme.inkSecondary).frame(width: 76, alignment: .leading)
                TextField("https://api.openai.com/v1", text: $byokURL)
                    .textFieldStyle(.plain).font(Theme.mono(12)).foregroundColor(Theme.inkPrimary)
                    .autocorrectionDisabled()
                    .onChange(of: byokURL) { _, v in UserDefaults.standard.set(v, forKey: AIBackend.urlKey) }
            }
            Hairline()
            row {
                Text("模型").font(Theme.ui(12.5)).foregroundColor(Theme.inkSecondary).frame(width: 76, alignment: .leading)
                TextField("gpt-4o-mini / deepseek-chat / …", text: $byokModel)
                    .textFieldStyle(.plain).font(Theme.mono(12)).foregroundColor(Theme.inkPrimary)
                    .autocorrectionDisabled()
                    .onChange(of: byokModel) { _, v in UserDefaults.standard.set(v, forKey: AIBackend.modelKey) }
            }
            Hairline()
            row {
                Text("API Key").font(Theme.ui(12.5)).foregroundColor(Theme.inkSecondary).frame(width: 76, alignment: .leading)
                SecureField("sk-…", text: $byokKey)
                    .textFieldStyle(.plain).font(Theme.mono(12)).foregroundColor(Theme.inkPrimary)
                    .onChange(of: byokKey) { _, v in AIBackend.setAPIKey(v) }
                Spacer()
                Text("存于系统钥匙串").font(Theme.mono(9.5)).foregroundColor(Theme.inkMuted)
            }
            Hairline()
            row {
                Text("兼容任意 OpenAI 格式端点（OpenAI / DeepSeek / Moonshot / 方舟…）")
                    .font(Theme.mono(10)).foregroundColor(Theme.inkMuted)
                Spacer()
                Button {
                    guard !testingAI else { return }
                    testingAI = true
                    Task {
                        let error = await AIBackend.test()
                        testingAI = false
                        store.showToast(error.map { "连接失败：\($0)" } ?? "连接正常")
                    }
                } label: {
                    HStack(spacing: 5) {
                        if testingAI { ProgressView().controlSize(.mini) }
                        Text("测试连接").font(Theme.ui(11.5, .semibold))
                    }
                    .foregroundColor(Theme.inkSecondary)
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(Theme.white).clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Theme.borderDefault, lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(testingAI || !AIBackend.isBYOK)
            }
        }
    }

    // MARK: 数据

    private var dataSection: some View {
        let diagnostics = KnowledgeStore.shared.diagnostics()
        return VStack(spacing: 0) {
            row {
                Toggle("", isOn: Binding(
                    get: { store.knowledgeEnabled },
                    set: { store.setKnowledgeEnabled($0) }
                ))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("工作知识库").font(Theme.ui(13)).foregroundColor(Theme.inkPrimary)
                    Text("关闭后停止新的知识任务并隐藏入口；不会删除本地数据")
                        .font(Theme.mono(9.5)).foregroundColor(Theme.inkMuted)
                }
                Spacer()
            }
            Hairline()
            row {
                Circle().fill(diagnostics.isClean ? Theme.green500 : Theme.danger500)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text("知识库诊断").font(Theme.ui(13)).foregroundColor(Theme.inkPrimary)
                    Text(diagnostics.error
                         ?? "schema v\(diagnostics.schemaVersion) · \(diagnostics.tableCounts["knowledge_units", default: 0]) 条知识 · \(diagnostics.tableCounts["extraction_jobs", default: 0]) 个任务")
                        .font(Theme.mono(9.5))
                        .foregroundColor(diagnostics.isClean ? Theme.inkMuted : Theme.danger500)
                }
                Spacer()
                Text(diagnostics.isClean ? "正常" : "需检查")
                    .font(Theme.mono(10.5, .semibold))
                    .foregroundColor(diagnostics.isClean ? Theme.green500 : Theme.danger500)
            }
            Hairline()
            row {
                Text("本地数据")
                    .font(Theme.ui(13)).foregroundColor(Theme.inkPrimary)
                Spacer()
                Button {
                    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("AfterMeet")
                    NSWorkspace.shared.activateFileViewerSelecting([base])
                } label: {
                    Text("打开数据目录").font(Theme.ui(11.5, .semibold)).foregroundColor(Theme.inkSecondary)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(Theme.white).clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Theme.borderDefault, lineWidth: 1))
                        .contentShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
    }

    // MARK: 底座

    private func row<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 11) { content() }
            .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func statusRow(_ label: String, ok: Bool, okText: String, failText: String) -> some View {
        row {
            Circle().fill(ok ? Theme.green500 : Theme.danger500).frame(width: 7, height: 7)
            Text(label).font(Theme.ui(13)).foregroundColor(Theme.inkPrimary)
            Spacer()
            Text(ok ? okText : failText).font(Theme.mono(11))
                .foregroundColor(ok ? Theme.inkTertiary : Theme.danger500)
        }
    }

    /// 扫描本机模型：历史目录 + app 模型目录里的 ggml-*.bin
    private func scanModels() {
        let dirs = [NSHomeDirectory() + "/Dev/clip/work/models", ModelDownloader.dir.path]
        var found: [(String, String)] = []
        let fmt = ByteCountFormatter()
        for dir in dirs {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            for f in files where f.hasPrefix("ggml-") && f.hasSuffix(".bin") {
                let path = (dir as NSString).appendingPathComponent(f)
                let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? nil
                found.append((path, size.map { fmt.string(fromByteCount: $0) } ?? "—"))
            }
        }
        localModels = found
        currentModel = Whisper.model
    }

}
