import Foundation
import CoreGraphics

/// "Is a real meeting/call window on screen right now?" — used to gate auto-record so the mic merely
/// being in use (Siri, a voice memo, anything) no longer triggers a recording.
///
/// Owner-name match is permission-free; reading window titles needs screen-recording (granted once
/// capture is authorized). The 飞书/Lark client is always running, so only its *call* window counts —
/// matched by a title hint for now, to be tightened against a real meeting via `logCandidates()`.
enum MeetingDetector {
    /// Dedicated meeting apps — an on-screen normal window basically means you're in/at a call.
    static let meetingApps = ["zoom.us", "腾讯会议", "wemeet", "Microsoft Teams", "Webex", "Cisco Webex", "GoToMeeting", "Skype"]
    /// Always-running clients — only their call window counts (matched by title hint).
    static let multiUseApps = ["Feishu", "飞书", "Lark"]
    static let callHints = ["会议", "通话", "视频通话", "Meeting", "Call", "Zoom Meeting"]

    private static let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("aftermeet-capture.log")
    private static func log(_ s: String) {
        guard let d = (s + "\n").data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(d); try? h.close() }
    }

    private static func onScreenWindows() -> [[String: Any]] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        return (CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]]) ?? []
    }

    static func meetingWindowPresent() -> Bool {
        for w in onScreenWindows() {
            guard (w[kCGWindowLayer as String] as? Int) == 0 else { continue }     // normal windows, not status items
            let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
            let title = (w[kCGWindowName as String] as? String) ?? ""
            if meetingApps.contains(where: { owner.localizedCaseInsensitiveContains($0) }) { return true }
            if multiUseApps.contains(where: { owner.localizedCaseInsensitiveContains($0) }),
               callHints.contains(where: { title.localizedCaseInsensitiveContains($0) }) { return true }
        }
        return false
    }

    /// Dump candidate windows from meeting-ish apps — read these lines from `~/aftermeet-capture.log`
    /// during a real 飞书 meeting to learn its exact VC window (owner/title), then tighten the match.
    static func logCandidates() {
        let watch = meetingApps + multiUseApps
        var any = false
        for w in onScreenWindows() {
            let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
            guard watch.contains(where: { owner.localizedCaseInsensitiveContains($0) }) else { continue }
            let title = (w[kCGWindowName as String] as? String) ?? ""
            let layer = (w[kCGWindowLayer as String] as? Int) ?? -1
            log("  [win] owner=\(owner) layer=\(layer) title=\(title.isEmpty ? "<empty>" : title)")
            any = true
        }
        if !any { log("  [win] (麦克风活跃但屏上无会议类窗口)") }
    }
}
