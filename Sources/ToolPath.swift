import Foundation
import AppKit

/// 外部 CLI 的路径发现 —— 不再假设 Apple Silicon Homebrew 一种安装方式。
/// 顺序：ARM brew → Intel brew/手动 → ~/.local/bin → ~/bin → 登录 shell 的 PATH
/// （npm/nvm 全局装的命令只有最后一种能找到）。结果按工具名缓存。
enum ToolPath {
    nonisolated(unsafe) private static var cache: [String: String?] = [:]
    private static let lock = NSLock()

    /// GUI app 从 Dock 启动时 PATH 只有 /usr/bin:/bin —— shebang 为 `#!/usr/bin/env node`
    /// 的 CLI（npm 装的 lark-cli）会因找不到 node 秒退且无输出。
    /// 所有子进程统一带上补全的 PATH，终端里能跑的命令 app 里也要能跑。
    static let childEnvironment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        let cur = env["PATH"] ?? "/usr/bin:/bin"
        let present = Set(cur.split(separator: ":").map(String.init))
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin",
                     NSHomeDirectory() + "/.local/bin",
                     NSHomeDirectory() + "/bin"].filter { !present.contains($0) }
        env["PATH"] = (extra + [cur]).joined(separator: ":")
        return env
    }()

    /// 跑某个具体工具时用的环境：把该工具所在目录前置进 PATH。
    /// npm 全局装的 CLI（brew / nvm / volta / fnm / asdf）node 都和它在同一个 bin 目录，
    /// 这样无论装在哪，shebang 的 `env node` 都能找到 —— 不依赖枚举安装方式。
    static func environment(for toolPath: String) -> [String: String] {
        var env = childEnvironment
        let dir = (toolPath as NSString).deletingLastPathComponent
        if let path = env["PATH"], !path.split(separator: ":").map(String.init).contains(dir) {
            env["PATH"] = dir + ":" + path
        }
        return env
    }

    static func resolve(_ name: String) -> String? {
        lock.lock()
        if let hit = cache[name] { lock.unlock(); return hit }
        lock.unlock()

        let fm = FileManager.default
        // 内置优先：随 app 分发的引擎（Contents/MacOS/<name>）
        if let aux = Bundle.main.url(forAuxiliaryExecutable: name)?.path,
           fm.isExecutableFile(atPath: aux) {
            lock.lock(); cache[name] = aux; lock.unlock()
            return aux
        }
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            NSHomeDirectory() + "/.local/bin/\(name)",
            NSHomeDirectory() + "/bin/\(name)",
        ]
        var found = candidates.first { fm.isExecutableFile(atPath: $0) }

        if found == nil {
            // shell 兜底，只在候选全落空时跑：先登录 shell（.zprofile），
            // 再交互 shell（.zshrc —— nvm/volta 的初始化都在这里）。
            found = shellWhich(name, interactive: false) ?? shellWhich(name, interactive: true)
        }

        lock.lock(); cache[name] = found; lock.unlock()
        return found
    }

    /// 用用户的 shell 跑 `command -v`，3 秒超时（防 shell 初始化卡死）。
    /// 交互 shell 可能往 stdout 打招呼语，只认最后一行以 / 开头的可执行路径。
    private static func shellWhich(_ name: String, interactive: Bool) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = (interactive ? ["-i", "-l", "-c"] : ["-l", "-c"]) + ["command -v \(name)"]
        let out = Pipe(); p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        var buf = Data()
        let eof = DispatchSemaphore(value: 0)
        out.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; eof.signal() } else { buf.append(d) }
        }
        let deadline = Date().addingTimeInterval(3)
        while p.isRunning && Date() < deadline { usleep(50_000) }
        if p.isRunning { p.terminate(); usleep(200_000); if p.isRunning { kill(p.processIdentifier, SIGKILL) } }
        _ = eof.wait(timeout: .now() + 1)
        out.fileHandleForReading.readabilityHandler = nil
        let lines = String(data: buf, encoding: .utf8)?
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        return lines.last(where: { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) })
    }
}
