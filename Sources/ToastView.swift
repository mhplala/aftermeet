import SwiftUI

struct ToastView: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.green500).frame(width: 16, height: 16)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
            }
            Text(text)
                .font(Theme.ui(13.5, .medium))
                .foregroundColor(Theme.onDark)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(Theme.ink1000)
        .clipShape(Capsule())
        .popShadow()
    }
}
