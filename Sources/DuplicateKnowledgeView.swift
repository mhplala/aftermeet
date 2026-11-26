import SwiftUI

struct DuplicateKnowledgeView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let review: KnowledgeDuplicateReview
    @State private var primaryID: String

    init(review: KnowledgeDuplicateReview) {
        self.review = review
        let preferred = review.items.first {
            $0.unit.reviewStatus == .confirmed || $0.unit.reviewStatus == .edited
        } ?? review.items[0]
        _primaryID = State(initialValue: preferred.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("选择要保留的主知识。其余条目会标为已忽略，证据会合并到主条目，并保留 same_as 关系和审计记录。")
                        .font(Theme.ui(12)).foregroundColor(Theme.inkSecondary)
                        .lineSpacing(3).padding(.bottom, 4)
                    ForEach(review.items) { item in
                        option(item)
                    }
                }
                .padding(20)
            }
            Hairline()
            footer
        }
        .frame(width: 660, height: 560)
        .background(Theme.canvas)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("处理重复知识")
                    .font(Theme.display(15, .semibold)).foregroundColor(Theme.inkPrimary)
                Text("\(review.items.count) 条 · 指纹 \(review.id.prefix(10))")
                    .font(Theme.mono(9.5)).foregroundColor(Theme.inkTertiary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.inkSecondary)
                    .frame(width: 28, height: 28).background(Theme.warmWhite2).clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(Theme.white)
    }

    private func option(_ item: KnowledgeInboxItem) -> some View {
        let selected = primaryID == item.id
        let source = item.sources.first
        let meeting = source.flatMap { value in
            store.meetings.first(where: { $0.id == value.meetingID })?.title
        } ?? source?.meetingID ?? "来源未知"
        return Button { primaryID = item.id } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15)).foregroundColor(selected ? Theme.inkPrimary : Theme.inkMuted)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        Text(selected ? "保留" : "合并")
                            .font(Theme.mono(9.5, .semibold))
                            .foregroundColor(selected ? Theme.green700 : Theme.inkTertiary)
                        if item.unit.reviewStatus == .confirmed || item.unit.reviewStatus == .edited {
                            Text("已审核")
                                .font(Theme.mono(9.5, .semibold)).foregroundColor(Theme.blue700)
                        }
                    }
                    Text(item.unit.canonicalText)
                        .font(Theme.ui(13.5, .medium)).foregroundColor(Theme.inkPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(meeting) · \(item.evidence.count) 条证据")
                        .font(Theme.mono(9.5)).foregroundColor(Theme.inkTertiary)
                }
                Spacer()
            }
            .padding(14)
            .background(selected ? Theme.warmWhite : Theme.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous)
                    .strokeBorder(selected ? Theme.borderStrong : Theme.borderWhisper, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Text("不会删除原始知识或会议证据")
                .font(Theme.mono(9.5)).foregroundColor(Theme.inkTertiary)
            Spacer()
            Button("取消") { dismiss() }
                .buttonStyle(.plain)
                .font(Theme.ui(11.5, .semibold)).foregroundColor(Theme.inkSecondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
            Button {
                if store.mergeDuplicateKnowledge(primaryID: primaryID) { dismiss() }
            } label: {
                Text("合并其余 \(max(0, review.items.count - 1)) 条")
                    .font(Theme.ui(11.5, .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Theme.inkGrad).clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.vertical, 13)
        .background(Theme.white)
    }
}
