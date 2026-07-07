import SwiftUI

// MARK: - Whisper 模型下载器（hf-mirror 直连；内网被拦时诚实报错）

@MainActor
final class ModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var progress: [String: Double] = [:]     // 文件名 → 0…1
    @Published var errors: [String: String] = [:]
    private var names: [Int: String] = [:]               // taskIdentifier → 文件名

    static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AfterMeet/models")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    func download(_ file: String) {
        guard progress[file] == nil else { return }
        guard let url = URL(string: "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/\(file)") else { return }
        errors[file] = nil
        progress[file] = 0
        let task = session.downloadTask(with: url)
        names[task.taskIdentifier] = file
        task.resume()
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
                self.progress[f] = nil
                self.errors[f] = "下载失败（HTTP \(code)）"
                try? FileManager.default.removeItem(at: tmp)
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
                self.progress[f] = nil
                self.errors[f] = "网络错误：\(error.localizedDescription)"
                self.names[id] = nil
            }
        }
    }
}

// MARK: - 设置页

struct SettingsScreen: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var downloader = ModelDownloader()
    @State private var currentModel = Whisper.model
    @State private var localModels: [(path: String, size: String)] = []
    @State private var usage: String = ""

    /// 可下载的常用模型（多语种，中文可用；q5 为量化版，体积小速度快）
    private let downloadable: [(file: String, label: String, size: String)] = [
        ("ggml-small.bin",             "Small · 快，精度一般",        "466 MB"),
        ("ggml-medium-q5_0.bin",       "Medium Q5 · 推荐，中文较准",  "514 MB"),
        ("ggml-large-v3-turbo-q5_0.bin", "Large v3 Turbo Q5 · 最准", "547 MB"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Overline("偏好与状态", tracking: 1.2).padding(.bottom, 8)
                Text("设置")
                    .font(Theme.display(36, .semibold)).tracking(-0.8)
                    .foregroundColor(Theme.inkPrimary)
                    .padding(.bottom, 20)

                section("转写模型") { modelSection }
                section("录制") { recordSection }
                section("飞书") { larkSection }
                section("AI 服务") { aiSection }
                section("数据") { dataSection }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
        .onAppear { scanModels(); fetchUsage() }
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
                            Text(m.path).font(Theme.mono(9.5)).foregroundColor(Theme.inkMuted)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(m.size).font(Theme.mono(11)).foregroundColor(Theme.inkTertiary)
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
                Text("下载源 hf-mirror.com；公司内网可能拦截，失败时请手动下载后放入模型目录。")
                    .font(Theme.mono(10)).foregroundColor(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button { NSWorkspace.shared.activateFileViewerSelecting([ModelDownloader.dir]) } label: {
                    Text("打开模型目录").font(Theme.ui(11.5, .semibold)).foregroundColor(Theme.inkSecondary)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(Color.white).clipShape(Capsule())
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
        }
    }

    // MARK: 飞书

    private var larkSection: some View {
        VStack(spacing: 0) {
            statusRow("lark-cli", ok: Lark.available,
                      okText: "已安装", failText: "未找到（brew install 后重启 app）")
            Hairline()
            row {
                VStack(alignment: .leading, spacing: 2) {
                    Text("消息发送权限").font(Theme.ui(13)).foregroundColor(Theme.inkPrimary)
                    Text("转发纪要到群需要 im:message.send_as_user").font(Theme.mono(9.5)).foregroundColor(Theme.inkMuted)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        "lark-cli auth login --scope \"im:message.send_as_user im:message\"", forType: .string)
                    store.showToast("授权命令已复制，在终端运行并完成浏览器授权")
                } label: {
                    Text("复制授权命令").font(Theme.ui(11.5, .semibold)).foregroundColor(Theme.inkSecondary)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(Color.white).clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Theme.borderDefault, lineWidth: 1))
                        .contentShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
    }

    // MARK: AI 服务

    private var aiSection: some View {
        VStack(spacing: 0) {
            row {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Siku 云（纪要提炼 / 问答）").font(Theme.ui(13)).foregroundColor(Theme.inkPrimary)
                    Text("设备标识 " + String(SikuCloud.deviceToken.suffix(12)))
                        .font(Theme.mono(9.5)).foregroundColor(Theme.inkMuted)
                }
                Spacer()
                Text(usage.isEmpty ? "…" : usage).font(Theme.mono(11)).foregroundColor(Theme.inkTertiary)
            }
        }
    }

    // MARK: 数据

    private var dataSection: some View {
        VStack(spacing: 0) {
            row {
                Text("会议 \(store.meetings.count) 场 · 转写档案实时落盘")
                    .font(Theme.ui(13)).foregroundColor(Theme.inkPrimary)
                Spacer()
                Button {
                    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("AfterMeet")
                    NSWorkspace.shared.activateFileViewerSelecting([base])
                } label: {
                    Text("打开数据目录").font(Theme.ui(11.5, .semibold)).foregroundColor(Theme.inkSecondary)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(Color.white).clipShape(Capsule())
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
        let dirs = ["/Users/steve/Dev/clip/work/models", ModelDownloader.dir.path]
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

    /// GET /v1/usage —— 今日 token 用量 / 配额（走和提炼同一条 SNI 绕过链路）
    private func fetchUsage() {
        Task.detached(priority: .utility) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            p.arguments = ["-sk", "--max-time", "15",
                           "https://\(Refine.ip)/v1/usage",
                           "-H", "Host: \(Refine.host)",
                           "-H", "Authorization: Bearer \(SikuCloud.deviceToken)",
                           "-H", "X-Siku-App: \(SikuCloud.appSecret)"]
            let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
            try? p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            var label = "用量读取失败"
            if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                let used = (json["used"] as? Int) ?? (json["used_today"] as? Int) ?? 0
                let quota = (json["daily_quota"] as? Int) ?? (json["quota"] as? Int) ?? 0
                if quota > 0 {
                    label = "今日 \(used / 1000)k / \(quota / 1_000_000)M token"
                } else if quota == -1 {
                    label = "今日 \(used / 1000)k token · 无限额"
                }
            }
            let final = label
            await MainActor.run { self.usage = final }
        }
    }
}
