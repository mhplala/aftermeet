import SwiftUI

struct EvidenceView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let evidence: KnowledgeInboxEvidence
    @State private var showsFullTranscript = false

    private var unit: KnowledgeUnit? {
        store.knowledgeInboxItems.first { $0.id == evidence.link.unitID }?.unit
    }

    private var allSegments: [KnowledgeSourceSegment] {
        store.knowledgeEvidenceWindow(for: evidence, fullMeeting: true)
    }

    private var context: [KnowledgeSourceSegment] {
        store.knowledgeEvidenceWindow(for: evidence)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let unit {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("正在核对的知识").font(Theme.ui(11, .semibold)).foregroundColor(Theme.inkSecondary)
                            Text(unit.canonicalText).font(Theme.ui(15, .medium)).foregroundColor(Theme.inkPrimary)
                                .textSelection(.enabled)
                            Text("引用原文：“\(evidence.link.quote)”")
                                .font(Theme.ui(12)).foregroundColor(Theme.inkSecondary).textSelection(.enabled)
                        }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.white).clipShape(RoundedRectangle(cornerRadius: Theme.rMD))
                    }
                    if let unit, let context = unit.topicContext {
                        KnowledgeTopicContextView(context: context,
                            evidence: store.knowledgeInboxItems.first { $0.id == unit.id }?.evidenceContexts ?? [])
                    }
                    KnowledgeMeetingContext(source: evidence.source, expanded: true)
                    HStack {
                        Text(showsFullTranscript ? "完整会议原文 · 高亮知识出处" : "知识出处及相邻讨论")
                            .font(Theme.ui(12, .semibold)).foregroundColor(Theme.inkPrimary)
                        Spacer()
                        if showsFullTranscript {
                            Button("定位知识出处") { proxy.scrollTo(evidence.segment.id, anchor: .center) }
                                .buttonStyle(.plain).font(Theme.ui(12, .medium)).foregroundColor(Theme.blue700)
                        }
                        Button(showsFullTranscript ? "收起完整原文" : "展开完整会议原文") {
                            showsFullTranscript.toggle()
                        }.buttonStyle(.plain).font(Theme.ui(12, .medium)).foregroundColor(Theme.blue700)
                    }
                    ForEach(showsFullTranscript ? allSegments : context) { segment in
                        segmentCard(segment).id(segment.id)
                    }
                    if showsFullTranscript && allSegments.isEmpty {
                        Text(evidence.source.fullText).font(Theme.ui(13)).foregroundColor(Theme.inkPrimary)
                            .textSelection(.enabled)
                    }
                }
                .padding(22)
            }
            }
            Hairline()
            footer
        }
        .frame(width: 820, height: 700)
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
                Text("知识与会议上下文")
                    .font(Theme.display(15, .semibold)).foregroundColor(Theme.inkPrimary)
                Text("会议背景 → 知识主张 → 原文出处")
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


}

/// The meeting summary provides orientation; the immutable source remains the evidence.
struct KnowledgeMeetingContext: View {
    @EnvironmentObject var store: AppStore
    let source: KnowledgeSourceDocument
    var expanded = false

    private var meeting: MeetingVM? { store.meetings.first { $0.id == source.meetingID } }

    private var summary: String {
        guard let meeting else { return "" }
        if !meeting.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return meeting.summary }
        return meeting.displayBlocks.first { $0.type == "summary" }?.text ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("来源会议 · " + (meeting?.title ?? "会议记录"))
                .font(Theme.ui(12.5, .semibold)).foregroundColor(Theme.inkPrimary)
            if let meeting {
                Text(meeting.metaParts.joined(separator: " · "))
                    .font(Theme.ui(10.5)).foregroundColor(Theme.inkTertiary)
                if !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(summary)
                        .font(Theme.ui(12)).foregroundColor(Theme.inkSecondary)
                        .lineSpacing(3).lineLimit(expanded ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if expanded {
                        Text("会议摘要用于理解背景，请结合下方原文判断知识是否成立。")
                            .font(Theme.ui(10.5)).foregroundColor(Theme.inkTertiary)
                    }
                } else {
                    Text("这场会议尚无摘要，可展开完整原文了解讨论背景。")
                        .font(Theme.ui(12)).foregroundColor(Theme.inkSecondary)
                }
            } else {
                Text("来源会议暂不在会议库中，保留的完整原文仍可查看。")
                    .font(Theme.ui(12)).foregroundColor(Theme.inkSecondary)
            }
        }
        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warmWhite2)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD))
    }
}

struct KnowledgeTopicContextView: View {
    @EnvironmentObject var store: AppStore
    let context: KnowledgeTopicContext
    let evidence: [KnowledgeInboxEvidence]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(context.topic).font(Theme.ui(13, .semibold)).foregroundColor(Theme.inkPrimary)
            statement("讨论背景", context.background)
            ForEach(Array(context.keyFacts.enumerated()), id: \.offset) { _, fact in statement("关键事实", fact) }
            ForEach(Array(context.rationale.enumerated()), id: \.offset) { _, reason in statement("判断与决策依据", reason) }
            if let scope = context.applicability { statement("适用范围", scope) }
            Text("留存价值 · " + context.significance).font(Theme.ui(11.5)).foregroundColor(Theme.inkSecondary)
            if !context.unknowns.isEmpty {
                Text("尚未确定 · " + context.unknowns.joined(separator: "；"))
                    .font(Theme.ui(11.5)).foregroundColor(Theme.warn500)
            }
            if context.retention == .historicalDecision {
                Text("历史决策 · 仅代表当时背景下的选择").font(Theme.ui(10.5)).foregroundColor(Theme.inkTertiary)
            }
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warmWhite2).clipShape(RoundedRectangle(cornerRadius: Theme.rMD))
    }

    private func statement(_ title: String, _ statement: KnowledgeContextStatement) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.ui(10.5, .semibold)).foregroundColor(Theme.inkTertiary)
            Text(statement.text).font(Theme.ui(12.5)).foregroundColor(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            ForEach(statement.segmentIDs, id: \.self) { id in
                if let source = evidence.first(where: { $0.segment.id == id }) {
                    Button { store.openKnowledgeEvidence(source) } label: {
                        Label("核对原文 · 第 \(source.segment.ordinal + 1) 段", systemImage: "quote.bubble")
                            .font(Theme.ui(10.5)).foregroundColor(Theme.blue700)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
