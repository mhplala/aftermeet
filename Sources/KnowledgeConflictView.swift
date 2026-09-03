import SwiftUI

struct KnowledgeConflictView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let review: KnowledgeConflictReview
    @State private var otherID: String

    init(review: KnowledgeConflictReview) {
        self.review = review
        _otherID = State(initialValue: review.alternatives[0].id)
    }

    private var selectedOther: KnowledgeInboxItem {
        review.alternatives.first(where: { $0.id == otherID }) ?? review.alternatives[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    comparison
                    if review.alternatives.count > 1 { alternativePicker }
                    resolutionOptions
                }
                .padding(22)
            }
        }
        .frame(width: 720, height: 620)
        .background(Theme.canvas)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("处理知识冲突")
                    .font(Theme.display(15, .semibold)).foregroundColor(Theme.inkPrimary)
                Text("两条原文都会保留，只记录它们之间的关系")
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

    private var comparison: some View {
        HStack(alignment: .top, spacing: 10) {
            knowledgeBox("当前条目", review.primary, selected: true)
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 12)).foregroundColor(Theme.inkMuted)
                .frame(width: 24)
            knowledgeBox("另一条", selectedOther, selected: false)
        }
    }

    private func knowledgeBox(_ label: String,
                              _ item: KnowledgeInboxItem,
                              selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(label).font(Theme.mono(9.5, .semibold)).foregroundColor(Theme.inkTertiary)
            Text(item.unit.canonicalText)
                .font(Theme.ui(13, .medium)).foregroundColor(Theme.inkPrimary)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(sourceLabel(item))
                .font(Theme.mono(9)).foregroundColor(Theme.inkTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .background(selected ? Theme.warmWhite : Theme.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
        .hairline(selected ? Theme.borderStrong : Theme.borderWhisper, radius: Theme.rMD)
    }

    private var alternativePicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("选择要比较的另一条")
                .font(Theme.mono(9.5, .semibold)).foregroundColor(Theme.inkTertiary)
            Picker("另一条知识", selection: $otherID) {
                ForEach(review.alternatives) { item in
                    Text(item.unit.canonicalText).tag(item.id)
                }
            }
            .labelsHidden().pickerStyle(.menu)
        }
    }

    private var resolutionOptions: some View {
        VStack(spacing: 9) {
            resolutionButton(
                title: "并列保留",
                detail: "两条都可能在各自语境中成立，只结束冲突提醒。",
                icon: "equal",
                resolution: .keepBoth)
            resolutionButton(
                title: "当前条目取代另一条",
                detail: "给另一条写入有效期结束时间，并建立 supersedes 关系。",
                icon: "arrow.right.circle",
                resolution: .supersedes)
            resolutionButton(
                title: "明确相互矛盾",
                detail: "保留两条有效期，建立 contradicts 关系供查询时提示。",
                icon: "exclamationmark.arrow.triangle.2.circlepath",
                resolution: .contradicts)
        }
    }

    private func resolutionButton(title: String,
                                  detail: String,
                                  icon: String,
                                  resolution: KnowledgeConflictResolution) -> some View {
        Button {
            if store.resolveKnowledgeConflict(otherID: otherID, resolution: resolution) { dismiss() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14)).foregroundColor(Theme.inkSecondary)
                    .frame(width: 25)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Theme.ui(12.5, .semibold)).foregroundColor(Theme.inkPrimary)
                    Text(detail).font(Theme.ui(10.5)).foregroundColor(Theme.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.inkMuted)
            }
            .padding(13)
            .background(Theme.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
            .hairline(Theme.borderWhisper, radius: Theme.rMD)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sourceLabel(_ item: KnowledgeInboxItem) -> String {
        guard let source = item.sources.first else { return "来源未知" }
        return store.meetings.first(where: { $0.id == source.meetingID })?.title ?? source.meetingID
    }
}
