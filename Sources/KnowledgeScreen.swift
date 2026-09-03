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
            Text("把会议里的事实、决策与行动连接成可追溯、可更新的工作脉络。")
                .font(Theme.display(15, .regular))
                .foregroundColor(Theme.inkSecondary)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 3) {
            tab(.inbox, title: "确认箱", count: candidates.count)
            tab(.projects, title: "项目", count: store.knowledgeProjects.filter { $0.status != .archived }.count)
            tab(.ask, title: "问我的工作", count: nil)
        }
        .padding(3)
        .background(Theme.warmWhite2)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous)
            .strokeBorder(Theme.borderWhisper, lineWidth: 1))
        .frame(maxWidth: 430, alignment: .leading)
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
        let running = store.knowledgeJobs.filter { $0.state == .running }.count
        let waiting = store.knowledgeJobs.filter { $0.state == .pending || $0.state == .retry }.count
        let failed = store.knowledgeJobs.filter { $0.state == .failed }.count
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
