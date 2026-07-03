import Foundation
import Darwin   // kill / SIGKILL

/// Runs whisper.cpp's `whisper-server` as a resident child process (model loaded once)
/// and transcribes audio windows over HTTP. Resident model → ~0.1s/window, fast enough
/// to re-transcribe a growing window every ~1.5s for a live, streaming feel.
final class WhisperServer {
    private let exe = "/opt/homebrew/bin/whisper-server"
    private let port: Int
    private var proc: Process?

    init(port: Int = 8178) { self.port = port }

    func start() {
        guard proc == nil,
              FileManager.default.isExecutableFile(atPath: exe),
              Whisper.available() else { return }
        // kill any orphan still holding our port before we bind it (guards against past leaks)
        _ = capture("/usr/bin/pkill", ["-9", "-f", "whisper-server.*\(port)"])
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = ["-m", Whisper.model, "-l", "zh",
                       "--prompt", "以下是简体中文普通话会议记录。",
                       "--suppress-nst",            // suppress non-speech tokens
                       "--no-speech-thold", "0.45", // drop near-silence more aggressively (default 0.6)
                       "--host", "127.0.0.1", "--port", "\(port)"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice  // resident server — drain to null so a full pipe can't wedge it
        do { try p.run(); proc = p } catch { proc = nil }
    }

    func stop() {
        if let p = proc {
            kill(p.processIdentifier, SIGKILL)   // SIGKILL — a wedged server ignores SIGTERM
            p.waitUntilExit()
        }
        proc = nil
    }

    /// whisper-server wedges after sustained use — kill + relaunch + wait for the model to reload.
    func restart() {
        stop()
        start()
        waitReady()
    }

    private func waitReady(timeout: Double = 8) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let code = capture("/usr/bin/curl",
                                  ["-s", "-o", "/dev/null", "-w", "%{http_code}",
                                   "--max-time", "1", "http://127.0.0.1:\(port)/"]),
               !code.isEmpty, code != "000" {
                return
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    /// afconvert the window → 16k int16, POST to the resident server, return transcript text.
    func infer(wav: URL) -> String {
        let conv = wav.deletingPathExtension().appendingPathExtension("16k.wav")
        defer { try? FileManager.default.removeItem(at: conv) }
        guard runProc("/usr/bin/afconvert",
                      ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", wav.path, conv.path]) else { return "" }
        return curlInfer(conv)
    }

    private func curlInfer(_ wav: URL) -> String {
        guard let out = capture("/usr/bin/curl",
                                ["-s", "--max-time", "4",   // short → a wedge is detected fast
                                 "http://127.0.0.1:\(port)/inference",
                                 "-F", "file=@\(wav.path)", "-F", "response_format=text"])
        else { return "" }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    private func runProc(_ exe: String, _ args: [String]) -> Bool {
        capture(exe, args) != nil
    }

    private func capture(_ exe: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
