import SwiftUI

struct KnowledgeBackfillPanel: View {
    @EnvironmentObject var store: AppStore

    private var progress: KnowledgeBackfillProgress { store.knowledgeBackfillProgress }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous)
                        .fill(Theme.warmWhite2).frame(width: 36, height: 36)
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 14)).foregroundColor(Theme.inkSecondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(progress.total == 0 ? "历史知识试跑" : "知识提炼进度")
                        .font(Theme.ui(13.5, .semibold)).foregroundColor(Theme.inkPrimary)
                    Text(progress.total == 0
                         ? "先选择最近 10 场非敏感本地会议；不会自动处理全部历史。"
                         : progressText)
                        .font(Theme.ui(11)).foregroundColor(Theme.inkSecondary)
                }
                Spacer()
                controls
            }

            if progress.total > 0 {
                ProgressView(value: progress.fraction)
                    .tint(Theme.inkPrimary)
                HStack(spacing: 12) {
                    metric("总计", progress.total)
                    metric("完成", progress.completed)
                    metric("等待", progress.waiting + progress.running)
                    metric("失败", progress.failed)
                    metric("候选", progress.candidateUnits)
                    Spacer()
                    Text("剩余 \(progress.waiting + progress.running) 个来源")
                        .font(Theme.mono(9.5)).foregroundColor(Theme.inkTertiary)
                }
            }
        }
        .padding(16)
        .background(Theme.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rLG, style: .continuous))
        .hairline(Theme.borderWhisper, radius: Theme.rLG)
        .whisperShadow()
        .padding(.bottom, 14)
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 7) {
            if store.archiveScanLoading {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("检查档案中")
                }
                .font(Theme.ui(10.5, .medium)).foregroundColor(Theme.inkTertiary)
            } else if !store.knowledgeBackfillRunning {
                secondaryButton("检查转写档案", icon: "doc.text.magnifyingglass") {
                    store.startArchiveReviewScan()
                }
            }
            if progress.failed > 0 && !store.knowledgeBackfillRunning {
                secondaryButton("重试失败", icon: "arrow.clockwise") {
                    store.retryFailedKnowledgeJobs()
                }
            }
            if store.knowledgeBackfillRunning {
                secondaryButton("暂停", icon: "pause") {
                    store.pauseKnowledgeBackfill()
                }
            } else if progress.waiting > 0 {
                primaryButton("继续") { store.continueKnowledgeBackfill() }
            } else if progress.total == 0 {
                primaryButton("试跑 10 场") { store.startKnowledgePilot() }
            }
        }
    }

    private var progressText: String {
        if store.knowledgeBackfillRunning { return "正在逐个处理；点击暂停后会在当前来源完成时停下。" }
        if progress.failed > 0 { return "有失败任务待处理；已完成结果和断点都保留。" }
        if progress.waiting > 0 { return "队列已暂停，继续后会从持久断点恢复。" }
        return "本轮试跑已结束，请先审核候选，再决定是否扩大范围。"
    }

    private func metric(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 4) {
            Text(label).font(Theme.mono(9)).foregroundColor(Theme.inkTertiary)
            Text("\(value)").font(Theme.mono(10, .semibold)).foregroundColor(Theme.inkPrimary)
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.ui(11.5, .semibold)).foregroundColor(.white)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(Theme.inkGrad).clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(_ title: String,
                                 icon: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10))
                Text(title)
            }
            .font(Theme.ui(11.5, .semibold)).foregroundColor(Theme.inkSecondary)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(Theme.warmWhite2).clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
