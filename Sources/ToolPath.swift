import Foundation
import AppKit

/// 外部 CLI 的路径发现 —— 不再假设 Apple Silicon Homebrew 一种安装方式。
/// 顺序：ARM brew → Intel brew/手动 → ~/.local/bin → ~/bin → 登录 shell 的 PATH
/// （npm/nvm 全局装的命令只有最后一种能找到）。结果按工具名缓存。
enum ToolPath {
    nonisolated(unsafe) private static var cache: [String: String?] = [:]
    private static let lock = NSLock()

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
            // 登录 shell 兜底（会跑用户的 zshrc，只在候选全落空时用一次）
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", "command -v \(name)"]
            let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
            if (try? p.run()) != nil {
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let s = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !s.isEmpty, fm.isExecutableFile(atPath: s) { found = s }
            }
        }

        lock.lock(); cache[name] = found; lock.unlock()
        return found
    }
}
