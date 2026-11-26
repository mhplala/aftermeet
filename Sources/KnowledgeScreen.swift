import SwiftUI

struct KnowledgeScreen: View {
    @EnvironmentObject var store: AppStore

    private var candidates: [KnowledgeUnit] {
        store.knowledgeUnits.filter { $0.reviewStatus == .candidate }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                tabBar
                    .padding(.top, 22)
                    .padding(.bottom, 18)
                if let reason = store.knowledgeUnavailableReason {
                    unavailable(reason)
                } else {
                    if store.knowledgeTab == .inbox { KnowledgeBackfillPanel() }
                    jobStatus
                    tabContent
                }
            }
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
        .onAppear { store.refreshKnowledgeState() }
        .sheet(item: $store.selectedKnowledgeEvidence) { evidence in
            EvidenceView(evidence: evidence)
                .environmentObject(store)
        }
        .sheet(item: $store.editingKnowledgeUnit) { item in
            KnowledgeUnitEditorView(item: item)
                .environmentObject(store)
        }
        .sheet(item: $store.duplicateKnowledgeReview) { review in
            DuplicateKnowledgeView(review: review)
                .environmentObject(store)
        }
        .sheet(item: $store.conflictKnowledgeReview) { review in
            KnowledgeConflictView(review: review)
                .environmentObject(store)
        }
        .sheet(item: $store.archiveReviewSession) { session in
            KnowledgeArchiveReviewView(session: session)
                .environmentObject(store)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Overline("工作记忆 · 带原文证据", tracking: 1.0)
            Text("知识")
                .font(Theme.display(36, .semibold))
                .tracking(-0.8)
                .foregroundColor(Theme.inkPrimary)
            Text("候选是模型提出的主张；只有证据验证通过并由你确认后，才会成为可检索的知识。")
                .font(Theme.display(15, .regular))
                .foregroundColor(Theme.inkSecondary)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 3) {
            tab(.inbox, title: "候选确认", count: candidates.count)
            tab(.library, title: "知识库", count: store.knowledgeUnits.filter(\.isTrusted).count)
            tab(.projects, title: "项目", count: store.knowledgeProjects.filter { $0.status != .archived }.count)
            tab(.ask, title: "问我的工作", count: nil)
        }
        .padding(3)
        .background(Theme.warmWhite2)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous)
            .strokeBorder(Theme.borderWhisper, lineWidth: 1))
        .frame(maxWidth: 560, alignment: .leading)
    }

    private func tab(_ tab: KnowledgeTab, title: String, count: Int?) -> some View {
        let selected = store.knowledgeTab == tab
        return Button {
            withAnimation(.easeOut(duration: 0.16)) { store.knowledgeTab = tab }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(Theme.mono(9.5, .semibold))
                        .foregroundColor(selected ? Theme.inkPrimary : Theme.inkTertiary)
                }
            }
            .font(Theme.ui(12.5, selected ? .semibold : .medium))
            .foregroundColor(selected ? Theme.inkPrimary : Theme.inkSecondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selected ? Theme.white : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rSM, style: .continuous))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: Theme.rSM, style: .continuous)
                        .strokeBorder(Theme.borderWhisper, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var jobStatus: some View {
        let currentJobs = store.knowledgeJobs.filter {
            $0.extractorVersion == KnowledgeExtractionPrompt.extractorVersion
        }
        let running = currentJobs.filter { $0.state == .running }.count
        let waiting = currentJobs.filter { $0.state == .pending || $0.state == .retry }.count
        let failed = currentJobs.filter { $0.state == .failed }.count
        if running + waiting + failed > 0 {
            HStack(spacing: 9) {
                if running > 0 { ProgressView().controlSize(.small) }
                Circle()
                    .fill(failed > 0 ? Theme.danger500 : (running > 0 ? Theme.blue500 : Theme.inkMuted))
                    .frame(width: 6, height: 6)
                Text(jobStatusText(running: running, waiting: waiting, failed: failed))
                    .font(Theme.ui(11.5, .medium))
                    .foregroundColor(failed > 0 ? Theme.danger500 : Theme.inkSecondary)
                Spacer()
            }
            .padding(.horizontal, 13).padding(.vertical, 9)
            .background(Theme.warmWhite)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
            .padding(.bottom, 14)
        }
    }

    private func jobStatusText(running: Int, waiting: Int, failed: Int) -> String {
        var parts: [String] = []
        if running > 0 { parts.append("\(running) 个来源正在提炼") }
        if waiting > 0 { parts.append("\(waiting) 个等待处理") }
        if failed > 0 { parts.append("\(failed) 个失败待处理") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var tabContent: some View {
        switch store.knowledgeTab {
        case .inbox:
            KnowledgeInboxView()
        case .library:
            KnowledgeLibraryView()
        case .projects:
            if store.knowledgeProjects.filter({ $0.status != .archived }).isEmpty {
                empty(
                    icon: "square.stack.3d.up",
                    title: "还没有项目",
                    message: "项目由你创建或确认；模型只会建议归属，不会自动建项目。")
            } else {
                Card(padding: 20) {
                    Text("已建立 \(store.knowledgeProjects.count) 个项目")
                        .font(Theme.ui(14, .semibold)).foregroundColor(Theme.inkPrimary)
                }
            }
        case .ask:
            empty(
                icon: "text.bubble",
                title: "跨会议问答尚未开放",
                message: "先完成候选确认和项目归类，再用可信知识与原文片段回答。")
        }
    }

    private func empty(icon: String, title: String, message: String) -> some View {
        Card(padding: 0) {
            EmptyState(icon: icon, title: title, message: message)
        }
    }

    private func unavailable(_ reason: String) -> some View {
        Card(padding: 20) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 14)).foregroundColor(Theme.danger500)
                VStack(alignment: .leading, spacing: 4) {
                    Text("知识库暂不可用")
                        .font(Theme.ui(13.5, .semibold)).foregroundColor(Theme.inkPrimary)
                    Text(reason)
                        .font(Theme.ui(12)).foregroundColor(Theme.inkSecondary)
                        .textSelection(.enabled)
                }
                Spacer()
            }
        }
    }
}

struct KnowledgeLibraryView: View {
    @EnvironmentObject var store: AppStore

    private var items: [KnowledgeInboxItem] {
        store.knowledgeInboxItems.filter { $0.unit.isTrusted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.green700)
                VStack(alignment: .leading, spacing: 3) {
                    Text("这里才是可信知识")
                        .font(Theme.ui(12.5, .semibold)).foregroundColor(Theme.inkPrimary)
                    Text("每条知识都是一个原子主张，并保留原文证据、说话人、时间和验证状态。候选不会进入这里，也不会进入全局检索。")
                        .font(Theme.ui(11.5)).foregroundColor(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(13)
            .background(Theme.warmWhite)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))

            if items.isEmpty {
                Card(padding: 0) {
                    EmptyState(
                        icon: "checkmark.seal",
                        title: "还没有可信知识",
                        message: "候选通过语义与证据验证，并由你确认后，才会出现在这里。")
                }
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(items) { item in
                        knowledgeCard(item)
                    }
                }
            }
        }
    }

    private func knowledgeCard(_ item: KnowledgeInboxItem) -> some View {
        let evidence = item.evidenceContexts.first(where: { $0.link.evidenceRole == .support })
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Text(item.unit.reviewStatus == .edited ? "人工修订" : "已确认")
                    .font(Theme.mono(9.5, .semibold)).foregroundColor(Theme.green700)
                Text(claimTypeLabel(item.unit.claimType))
                    .font(Theme.mono(9.5, .semibold)).foregroundColor(Theme.inkSecondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Theme.warmWhite2).clipShape(Capsule())
                if item.unit.epistemicStatus != .certain {
                    Text(epistemicLabel(item.unit.epistemicStatus))
                        .font(Theme.mono(9.5, .semibold)).foregroundColor(Theme.warn500)
                }
                Spacer()
                Text(dateLabel(item.unit.observedAt))
                    .font(Theme.mono(9.5)).foregroundColor(Theme.inkTertiary)
            }

            Text(item.unit.canonicalText)
                .font(Theme.ui(14, .medium)).foregroundColor(Theme.inkPrimary)
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)

            let attributes = [
                item.unit.attributedTo.map { "归属 · \($0)" },
                item.unit.owner.map { "负责人 · \($0)" },
                item.unit.dueText.map { "时间 · \($0)" }
            ].compactMap { $0 }
            if !attributes.isEmpty {
                HStack(spacing: 7) {
                    ForEach(attributes, id: \.self) { value in
                        Text(value).font(Theme.mono(9.5)).foregroundColor(Theme.inkSecondary)
                    }
                }
            }

            if let evidence {
                if let context = item.unit.topicContext {
                    KnowledgeTopicContextView(context: context, evidence: item.evidenceContexts)
                } else {
                    Text("旧版知识 · 尚未按话题重新提炼").font(Theme.ui(11)).foregroundColor(Theme.inkTertiary)
                    KnowledgeMeetingContext(source: evidence.source)
                }

                Button { store.openKnowledgeEvidence(evidence) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("“\(evidence.link.quote)”")
                            .font(Theme.ui(12.5)).foregroundColor(Theme.inkSecondary)
                            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        Text("查看会议背景与完整原文")
                            .font(Theme.mono(9.5, .semibold)).foregroundColor(Theme.inkTertiary)
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.warmWhite)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.rSM, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(17)
        .background(Theme.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rLG, style: .continuous))
        .hairline(Theme.borderWhisper, radius: Theme.rLG)
        .whisperShadow()
    }

    private func claimTypeLabel(_ value: KnowledgeClaimType) -> String {
        switch value {
        case .observedFact: return "已观察事实"
        case .attributedOpinion: return "归属意见"
        case .forecast: return "预测"
        case .proposal: return "提议"
        case .decision: return "决定"
        case .commitment: return "承诺"
        case .statusUpdate: return "状态更新"
        case .openQuestion: return "待回答问题"
        }
    }

    private func epistemicLabel(_ value: KnowledgeEpistemicStatus) -> String {
        switch value {
        case .certain: return "确定"
        case .soft: return "弱表态"
        case .tentative: return "试探"
        case .conditional: return "有条件"
        }
    }

    private func dateLabel(_ timestamp: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}
