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

            NavItem(icon: "books.vertical", label: "会议",
                    active: store.screen == .library || store.screen == .detail) {
                store.libraryRawTab = false
                store.go(.library)
            }
            if store.knowledgeEnabled {
                NavItem(
                    icon: "brain.head.profile",
                    label: "知识",
                    badge: store.knowledgeBadge,
                    badgeColor: store.knowledgeAttentionCount > 0 ? Theme.warn500 : Theme.inkTertiary,
                    badgeWeight: store.knowledgeAttentionCount > 0 ? .semibold : .regular,
                    active: store.screen == .knowledge
                ) { store.go(.knowledge) }
            }
            NavItem(icon: "checklist", label: "行动项",
                    active: store.screen == .todos) { store.go(.todos) }
            NavItem(icon: "sun.max", label: "每日总结",
                    active: store.screen == .daily) { store.go(.daily) }
            Color.clear.frame(height: 8)
            NavItem(icon: "gearshape", label: "设置",
                    active: store.screen == .settings) { store.go(.settings) }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 20)
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(VisualEffect(material: .sidebar))   // 系统玻璃，不叠自定义色
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.borderWhisper).frame(width: 1)
        }
    }

    private var logo: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "5b93f8"), Color(hex: "2e6ae0")],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 30, height: 30)
                    .glow(Theme.blue500, radius: 8, opacity: 0.30)
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text("Aftermeet")
                .font(Theme.display(18, .semibold))
                .tracking(-0.3)
                .foregroundColor(Theme.inkPrimary)
        }
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
                        .strokeBorder(Theme.glassBorder, lineWidth: 1)
                }
            }
            .shadow(color: active ? Color.black.opacity(0.08) : .clear, radius: 5, x: 0, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var background: Color {
        if active { return Theme.glassFill }
        return hover ? Theme.hoverFill : Color.clear
    }
}
