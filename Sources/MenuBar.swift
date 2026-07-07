import SwiftUI
import AppKit

/// The menu-bar status-item glyph. Same waveform motif as the app icon; turns red while recording.
struct MenuBarLabel: View {
    @ObservedObject var capture: CaptureService
    var body: some View {
        Image(systemName: capture.isCapturing ? "waveform.circle.fill" : "waveform")
            .foregroundStyle(capture.isCapturing ? Color.red : Color.primary)
    }
}

/// Window-style dropdown for the menu-bar item: live status + one-tap start/stop, no main window needed.
struct MenuBarPanel: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var capture: CaptureService

    private var elapsedStr: String { String(format: "%d:%02d", capture.elapsed / 60, capture.elapsed % 60) }
    private var meetingLabel: String {
        let n = capture.meetingName.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { return n }
        let s = capture.calendarSuggestion.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "未命名会议" : s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "waveform").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
                Text("会后秘书").font(.system(size: 13, weight: .semibold))
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(capture.isCapturing ? Color.red : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                    Text(capture.isCapturing ? "录制中" : "空闲").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 11)

            Divider()

            Group {
                if capture.isCapturing {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(elapsedStr).font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                        Text(meetingLabel).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else {
                    Text("开始后，会中音频在本地实时转写，停止时自动生成纪要。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 11)

            Button(action: { store.toggleCapture() }) {
                HStack(spacing: 7) {
                    Image(systemName: capture.isCapturing ? "stop.fill" : "record.circle.fill")
                    Text(capture.isCapturing ? "停止并生成纪要" : "开始录制").font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(capture.isCapturing ? Color.red : Theme.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.bottom, 4)

            Divider()

            row("同步飞书会议", "arrow.triangle.2.circlepath") { store.syncNow() }
            row("打开主窗口", "macwindow") { activateMainWindow() }
            row("退出 AfterMeet", "power") { NSApplication.shared.terminate(nil) }
                .padding(.bottom, 6)
        }
        .frame(width: 264)
    }

    private func row(_ title: String, _ system: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: system).font(.system(size: 12)).frame(width: 15)
                Text(title).font(.system(size: 12.5))
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 14).padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.max(by: { $0.frame.width < $1.frame.width })?.makeKeyAndOrderFront(nil)
        if store.capture.isCapturing { store.showRecPanel = true }   // 录着呢 → 顺手展开录制面板
    }
}
