import Foundation

/// Best-effort meeting identification from the user's 飞书 calendar (already authorized).
/// Returns a *discrete* current meeting's name — skips all-day / cowork / placeholder blocks,
/// which is what the user's calendar mostly holds, so this is an auto-suggest, not the source of truth.
enum LarkCalendar {
    static let cli = "/opt/homebrew/bin/lark-cli"

    static func currentMeetingName() -> String? {
        guard FileManager.default.isExecutableFile(atPath: cli),
              let data = run([cli, "calendar", "+agenda", "--format", "json"]),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else { return nil }

        let now = Date()
        let iso = ISO8601DateFormatter()
        var candidates: [(name: String, hours: Double)] = []

        for ev in items {
            guard let summary = (ev["summary"] as? String)?.trimmingCharacters(in: .whitespaces), !summary.isEmpty,
                  let st = (ev["start_time"] as? [String: Any])?["datetime"] as? String,
                  let et = (ev["end_time"] as? [String: Any])?["datetime"] as? String,
                  let start = iso.date(from: st), let end = iso.date(from: et),
                  start <= now, now < end else { continue }

            let low = summary.lowercased()
            if low.contains("placeholder") || low.contains("cowork") || low.contains("co-work") || low.hasPrefix("[book]") { continue }
            let hours = end.timeIntervalSince(start) / 3600
            if hours > 4 { continue }                       // still-too-long blocks aren't a discrete meeting
            candidates.append((summary, hours))
        }
        // prefer the shortest current event — most likely the actual meeting
        return candidates.sorted { $0.hours < $1.hours }.first?.name
    }

    private static func run(_ args: [String]) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: args[0])
        p.arguments = Array(args.dropFirst())
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? d : nil
    }
}
