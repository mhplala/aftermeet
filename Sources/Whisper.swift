import Foundation

/// Local whisper.cpp transcription via the user's Homebrew `whisper-cli` + ggml model.
/// Shelled out with full paths (the GUI app's PATH lacks /opt/homebrew/bin), same as Refine's curl.
enum Whisper {
    static let cli = "/opt/homebrew/bin/whisper-cli"
    // ggml-medium-q5_0 (multilingual, quantized) — better zh accuracy, fast enough resident.
    // Override via UserDefaults "whisperModel".
    static var model: String {
        if let m = UserDefaults.standard.string(forKey: "whisperModel") { return m }
        let appModels = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AfterMeet/models")
        // 优先 app 模型目录（设置页下载的落这里），其次沿用历史开发路径
        let candidates = [
            appModels.appendingPathComponent("ggml-medium-q5_0.bin").path,
            appModels.appendingPathComponent("ggml-large-v3-turbo-q5_0.bin").path,
            appModels.appendingPathComponent("ggml-small.bin").path,
            NSHomeDirectory() + "/Dev/clip/work/models/ggml-medium-q5_0.bin",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates[0]
    }

    static func available() -> Bool {
        FileManager.default.isExecutableFile(atPath: cli) && FileManager.default.fileExists(atPath: model)
    }

    /// afconvert → 16 kHz int16 mono, then whisper-cli (zh). Returns plain transcript text.
    static func transcribe(wav: URL) -> String {
        let conv = wav.deletingPathExtension().appendingPathExtension("16k.wav")
        defer { try? FileManager.default.removeItem(at: conv) }
        guard run("/usr/bin/afconvert",
                  ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", wav.path, conv.path]) != nil,
              let out = run(cli, ["-m", model, "-l", "zh",
                                  "--prompt", "以下是简体中文普通话会议记录。",   // bias away from Traditional
                                  "-nt", "-np", "-f", conv.path])
        else { return "" }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    private static func run(_ exe: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
