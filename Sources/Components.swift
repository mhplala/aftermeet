import SwiftUI

// MARK: - Card container

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    var radius: CGFloat = Theme.rLG
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.white)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .hairline(Theme.borderWhisper, radius: radius)
            .whisperShadow()
    }
}

// MARK: - Mono overline label

struct Overline: View {
    let text: String
    var color: Color = Theme.inkTertiary
    var size: CGFloat = 10
    var tracking: CGFloat = 1.0

    var body: some View {
        Text(text)
            .font(Theme.mono(size, .semibold))
            .tracking(tracking)
            .textCase(.uppercase)
            .foregroundColor(color)
    }
}

// MARK: - Pill / tag

struct Pill: View {
    let text: String
    var bg: Color
    var fg: Color
    var size: CGFloat = 11.5

    var body: some View {
        Text(text)
            .font(Theme.ui(size, .semibold))
            .foregroundColor(fg)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(bg)
            .clipShape(Capsule())
    }
}

// MARK: - Avatar

struct Avatar: View {
    let initial: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        Text(initial)
            .font(Theme.display(size * 0.43, .medium))
            .foregroundColor(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.13))
            .clipShape(Circle())
    }
}

// MARK: - Stat card (dashboard metric)

struct StatCard: View {
    let label: String
    let value: String
    var unit: String? = nil
    let sub: String
    var subColor: Color = Theme.inkTertiary
    var valueColor: Color = Theme.inkPrimary
    var valueSize: CGFloat = 32

    var body: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 0) {
                Overline(label, color: Theme.inkTertiary, size: 10, tracking: 0.8)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(value)
                        .font(Theme.display(valueSize, .medium))
                        .tracking(-0.6)
                        .foregroundColor(valueColor)
                    if let unit {
                        Text(unit)
                            .font(Theme.display(valueSize * 0.56, .medium))
                            .foregroundColor(valueColor)
                    }
                }
                .padding(.top, 10)
                Text(sub)
                    .font(Theme.mono(11))
                    .foregroundColor(subColor)
                    .padding(.top, 6)
            }
        }
    }
}

extension Overline {
    init(_ text: String, color: Color = Theme.inkTertiary, size: CGFloat = 10, tracking: CGFloat = 1.0) {
        self.text = text
        self.color = color
        self.size = size
        self.tracking = tracking
    }
}

// MARK: - Section header dot

struct Dot: View {
    let color: Color
    var size: CGFloat = 8
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

// MARK: - Hairline divider

struct Hairline: View {
    var color: Color = Theme.borderWhisper
    var body: some View { Rectangle().fill(color).frame(height: 1) }
}

// MARK: - Honest empty state (data not yet accumulated)

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.warmWhite2).frame(width: 46, height: 46)
                Image(systemName: icon).font(.system(size: 19, weight: .regular)).foregroundColor(Theme.inkTertiary)
            }
            VStack(spacing: 6) {
                Text(title).font(Theme.display(16, .medium)).foregroundColor(Theme.inkPrimary)
                Text(message).font(Theme.ui(13)).foregroundColor(Theme.inkTertiary)
                    .multilineTextAlignment(.center).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40).padding(.horizontal, 24)
    }
}
