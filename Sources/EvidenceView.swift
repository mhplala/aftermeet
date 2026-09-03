import SwiftUI

struct EvidenceView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let evidence: KnowledgeInboxEvidence

    private var context: [KnowledgeSourceSegment] {
        store.knowledgeEvidenceWindow(for: evidence)
    }

    private var meetingTitle: String {
        store.meetings.first(where: { $0.id == evidence.source.meetingID })?.title
            ?? evidence.source.meetingID
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    sourceSummary
                    ForEach(context) { segment in
                        segmentCard(segment)
                    }
                }
                .padding(22)
            }
            Hairline()
            footer
        }
        .frame(width: 680, height: 540)
        .background(Theme.canvas)
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous)
                    .fill(Theme.warmWhite2).frame(width: 34, height: 34)
                Image(systemName: "quote.bubble")
                    .font(.system(size: 13)).foregroundColor(Theme.inkSecondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("原文证据")
                    .font(Theme.display(15, .semibold)).foregroundColor(Theme.inkPrimary)
                Text("命中片段前后各保留一段上下文")
                    .font(Theme.mono(9.5)).foregroundColor(Theme.inkTertiary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.inkSecondary)
                    .frame(width: 28, height: 28)
                    .background(Theme.warmWhite2).clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.vertical, 13)
        .background(Theme.white)
    }

    private var sourceSummary: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(meetingTitle)
                    .font(Theme.ui(13.5, .semibold)).foregroundColor(Theme.inkPrimary)
                Text("\(sourceLabel(evidence.source.sourceKind)) · \(evidence.source.contentHash.prefix(10))")
                    .font(Theme.mono(9.5)).foregroundColor(Theme.inkTertiary)
            }
            Spacer()
            if evidence.source.sensitivity == .restricted {
                Text("敏感来源")
                    .font(Theme.mono(9.5, .semibold)).foregroundColor(Theme.warn500)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.warn50).clipShape(Capsule())
            }
        }
        .padding(15)
        .background(Theme.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
        .hairline(Theme.borderWhisper, radius: Theme.rMD)
    }

    private func segmentCard(_ segment: KnowledgeSourceSegment) -> some View {
        let selected = segment.id == evidence.segment.id
        return HStack(alignment: .top, spacing: 13) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(position(segment))
                    .font(Theme.mono(9.5, selected ? .semibold : .regular))
                    .foregroundColor(selected ? Theme.inkPrimary : Theme.inkTertiary)
                if let speaker = segment.speaker, !speaker.isEmpty {
                    Text(speaker)
                        .font(Theme.ui(10.5, .medium)).foregroundColor(Theme.inkSecondary)
                }
            }
            .frame(width: 84, alignment: .trailing)
            Text(segment.text)
                .font(Theme.ui(13))
                .foregroundColor(selected ? Theme.inkPrimary : Theme.inkSecondary)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(selected ? Theme.warmWhite : Theme.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous)
                .strokeBorder(selected ? Theme.borderStrong : Theme.borderWhisper, lineWidth: 1)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("证据内容始终来自未经改写的原始片段")
                .font(Theme.mono(9.5)).foregroundColor(Theme.inkTertiary)
            Spacer()
            Button("关闭") { dismiss() }
                .buttonStyle(.plain)
                .font(Theme.ui(11.5, .semibold)).foregroundColor(Theme.inkSecondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Theme.warmWhite2).clipShape(Capsule())
            Button {
                store.openKnowledgeEvidenceMeeting(evidence)
            } label: {
                HStack(spacing: 5) {
                    Text("打开会议")
                    Image(systemName: "arrow.up.right")
                }
                .font(Theme.ui(11.5, .semibold)).foregroundColor(.white)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(Theme.inkGrad).clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!store.meetings.contains { $0.id == evidence.source.meetingID })
            .opacity(store.meetings.contains { $0.id == evidence.source.meetingID } ? 1 : 0.4)
        }
        .padding(.horizontal, 18).padding(.vertical, 13)
        .background(Theme.white)
    }

    private func position(_ segment: KnowledgeSourceSegment) -> String {
        if let start = segment.startMS {
            let seconds = max(0, start / 1_000)
            if seconds >= 3_600 {
                return String(format: "%d:%02d:%02d", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
            }
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
        return "字符 \(segment.charStart)–\(segment.charEnd)"
    }

    private func sourceLabel(_ source: KnowledgeSourceKind) -> String {
        switch source {
        case .liveCloud: return "云端转写"
        case .liveLocal: return "本地转写"
        case .feishu: return "飞书逐字稿"
        case .archive: return "历史档案"
        }
    }
}
