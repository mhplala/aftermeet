import SwiftUI

struct Sidebar: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // clear the traffic-light region (hidden title bar)
            Spacer().frame(height: 26)

            logo
                .padding(.horizontal, 8)
                .padding(.bottom, 18)

            NavItem(icon: "house", label: "概览",
                    active: store.screen == .home) { store.go(.home) }
            NavItem(icon: "waveform", label: "会中转写",
                    active: store.screen == .live) { store.go(.live) }
            NavItem(icon: "clock.arrow.circlepath", label: "转写历史",
                    active: store.screen == .history) { store.go(.history) }
            NavItem(icon: "doc.text", label: "会议纪要", badge: "\(store.meetings.count)",
                    active: store.screen == .detail) { store.go(.detail) }
            NavItem(icon: "checklist", label: "待办中心", badge: "\(store.openCount)",
                    badgeColor: Theme.accent, badgeWeight: .semibold,
                    active: store.screen == .todos) { store.go(.todos) }
            NavItem(icon: "clock.arrow.circlepath", label: "会前追问",
                    active: store.screen == .followup) { store.go(.followup) }
            NavItem(icon: "sun.max", label: "每日综述",
                    active: store.screen == .daily) { store.go(.daily) }
            NavItem(icon: "chart.line.uptrend.xyaxis", label: "周报",
                    active: store.screen == .weekly) { store.go(.weekly) }

            Text("账户")
                .font(Theme.mono(10, .semibold))
                .tracking(1.0)
                .foregroundColor(Theme.inkTertiary)
                .padding(.horizontal, 8)
                .padding(.top, 18)
                .padding(.bottom, 4)

            NavItem(icon: "sparkles", label: "接入引导", active: false) {
                store.obStep = 0
                store.showOnboarding = true
            }

            Spacer()

            statusCard
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 20)
        .frame(width: 248)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebarBg)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.borderWhisper).frame(width: 1)
        }
    }

    private var logo: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.accent)
                    .frame(width: 30, height: 30)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                (Text("会后").foregroundColor(Theme.inkPrimary)
                    + Text("秘书").foregroundColor(Theme.accent).italic())
                    .font(Theme.display(18, .medium))
                    .tracking(-0.3)
                Text("AFTERMEET")
                    .font(Theme.mono(9, .regular))
                    .tracking(1.6)
                    .foregroundColor(Theme.inkMuted)
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Theme.green500.opacity(0.25)).frame(width: 13, height: 13)
                    Circle().fill(Theme.green500).frame(width: 7, height: 7)
                }
                Text(store.sync.syncing ? "正在同步飞书会议…" : "秘书在线 · 监听中")
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.onDarkDim)
            }
            Text("会中自动转写；飞书纪要每 15 分钟扫一轮，会后自动送达。")
                .font(Theme.ui(12))
                .foregroundColor(Theme.onDarkDim)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button { store.syncNow() } label: {
                    Text("立即同步")
                        .font(Theme.mono(10, .semibold))
                        .foregroundColor(Theme.onDark)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(store.sync.syncing)
                Spacer()
                if !store.sync.lastSyncLabel.isEmpty {
                    Text(store.sync.lastSyncLabel)
                        .font(Theme.mono(9)).foregroundColor(Theme.onDarkDim)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ink1000)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rLG, style: .continuous))
    }
}

// MARK: - Nav item

struct NavItem: View {
    let icon: String
    let label: String
    var badge: String? = nil
    var badgeColor: Color = Theme.inkTertiary
    var badgeWeight: Font.Weight = .regular
    let active: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(active ? Theme.inkPrimary : Theme.inkSecondary)
                    .frame(width: 18)
                Text(label)
                    .font(Theme.ui(13.5, active ? .medium : .regular))
                    .foregroundColor(active ? Theme.inkPrimary : Theme.inkSecondary)
                Spacer(minLength: 0)
                if let badge {
                    Text(badge)
                        .font(Theme.mono(11, badgeWeight))
                        .foregroundColor(badgeColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rSM, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var background: Color {
        if active { return Color.black.opacity(0.06) }
        return hover ? Color.black.opacity(0.035) : Color.clear
    }
}
