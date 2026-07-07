import SwiftUI

struct Sidebar: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // clear the traffic-light region (hidden title bar)
            Spacer().frame(height: 44)

            logo
                .padding(.horizontal, 8)
                .padding(.bottom, 18)

            NavItem(icon: "house", label: "概览",
                    active: store.screen == .home) { store.go(.home) }

            group("会议")
            NavItem(icon: "books.vertical", label: "会议库", badge: "\(store.meetings.count)",
                    active: store.screen == .library || store.screen == .detail) { store.go(.library) }

            group("跟进")
            NavItem(icon: "checklist", label: "待办中心", badge: "\(store.openCount)",
                    badgeColor: Theme.accent, badgeWeight: .semibold,
                    active: store.screen == .todos) { store.go(.todos) }
            NavItem(icon: "clock.arrow.circlepath", label: "会前追问",
                    active: store.screen == .followup) { store.go(.followup) }

            group("回顾")
            NavItem(icon: "sun.max", label: "每日综述",
                    active: store.screen == .daily) { store.go(.daily) }
            NavItem(icon: "chart.line.uptrend.xyaxis", label: "周报",
                    active: store.screen == .weekly) { store.go(.weekly) }

            group("账户")
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
        .background(VisualEffect(material: .sidebar))   // 系统玻璃，不叠自定义色
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.borderWhisper).frame(width: 1)
        }
    }

    private func group(_ title: String) -> some View {
        Text(title)
            .font(Theme.mono(10, .semibold))
            .tracking(1.1)
            .foregroundColor(Theme.inkMuted)
            .padding(.horizontal, 8)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    private var logo: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.inkGrad)
                    .frame(width: 30, height: 30)
                    .glow(Color.black, radius: 8, opacity: 0.25)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
            Text("Aftermeet")
                .font(Theme.display(18, .semibold))
                .tracking(-0.3)
                .foregroundColor(Theme.inkPrimary)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Theme.accentGlow.opacity(0.22)).frame(width: 13, height: 13)
                    Circle().fill(Theme.accentGlow).frame(width: 7, height: 7)
                        .glow(Theme.accentGlow, radius: 6, opacity: 0.8)
                }
                Text(store.sync.syncing ? "正在同步飞书会议…" : "自动记录已开启")
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.onDarkDim)
            }
            Text("会议自动转写，飞书纪要每 15 分钟自动同步。")
                .font(Theme.ui(12))
                .foregroundColor(Theme.onDarkDim)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button { store.syncNow() } label: {
                    Text("立即同步")
                        .font(Theme.mono(10, .semibold))
                        .foregroundColor(Theme.onDark)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
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
        .background(Theme.inkGlass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rLG, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rLG, style: .continuous)
            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.22), radius: 12, x: 0, y: 7)
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
                    .font(.system(size: 14, weight: .regular))
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
            .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
            .overlay {
                if active {
                    RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                }
            }
            .shadow(color: active ? Color.black.opacity(0.08) : .clear, radius: 5, x: 0, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var background: Color {
        if active { return Color.white.opacity(0.82) }
        return hover ? Color.white.opacity(0.5) : Color.clear
    }
}
