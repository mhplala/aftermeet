import SwiftUI

struct TopBar: View {
    @State private var query = ""
    @State private var bellHover = false

    var body: some View {
        HStack(spacing: 14) {
            search
                .frame(maxWidth: 380)
            Spacer()
            Text("6月14日 周六")
                .font(Theme.mono(11.5))
                .foregroundColor(Theme.inkTertiary)
            bell
            avatar
        }
        .padding(.horizontal, 28)
        .frame(height: 60)
        .background(Theme.white)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.inkTertiary)
            TextField("搜索会议、待办、负责人…", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.ui(13))
            Text("⌘K")
                .font(Theme.mono(10))
                .foregroundColor(Theme.inkTertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Theme.white)
                .hairline(Theme.borderDefault, radius: 3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.searchBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
        .hairline(Theme.borderDefault, radius: Theme.rMD)
    }

    private var bell: some View {
        Button {} label: {
            Image(systemName: "bell")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(Theme.inkPrimary.opacity(0.8))
                .frame(width: 34, height: 34)
                .background(bellHover ? Theme.warmWhite : Theme.white)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
                .hairline(Theme.borderDefault, radius: Theme.rMD)
        }
        .buttonStyle(.plain)
        .onHover { bellHover = $0 }
    }

    private var avatar: some View {
        Text("林")
            .font(Theme.display(15, .medium))
            .foregroundColor(.white)
            .frame(width: 34, height: 34)
            .background(
                LinearGradient(colors: [Color(hex: "1f7a4c"), Color(hex: "3aa873")],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(Circle())
    }
}
