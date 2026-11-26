import SwiftUI

private enum ArchiveReviewFilter: String, CaseIterable, Identifiable {
    case ambiguous
    case orphan
    var id: String { rawValue }
}

struct KnowledgeArchiveReviewView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let session: ArchiveReviewSession
    @State private var filter: ArchiveReviewFilter = .ambiguous
    @State private var selectedMeeting: [String: String] = [:]
    @State private var busyRecords = Set<String>()

    private var report: ArchiveMatchReport {
        store.archiveReviewSession?.report ?? session.report
    }

    private var records: [ArchiveMatchRecord] {
        report.records.filter {
            switch filter {
            case .ambiguous: return $0.status == .ambiguous
            case .orphan: return $0.status == .orphan
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            summary
            filterBar
            ScrollView {
                if records.isEmpty {
                    EmptyState(
                        icon: filter == .ambiguous ? "checkmark.seal" : "tray",
                        title: filter == .ambiguous ? "没有待确认匹配" : "没有孤立档案",
                        message: filter == .ambiguous
                            ? "时间近似不会被自动采用，只有你确认后才会绑定。"
                            : "未对应会议的转写会出现在这里。")
                        .padding(.vertical, 44)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(records) { record in recordCard(record) }
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 760, height: 660)
        .background(Theme.canvas)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("转写档案审核")
                    .font(Theme.display(15, .semibold)).foregroundColor(Theme.inkPrimary)
                Text("扫描本身只生成报告，不创建会议或提炼任务")
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

    private var summary: some View {
        HStack(spacing: 18) {
            metric("已匹配", report.matchedCount)
            metric("待确认", report.ambiguousCount)
            metric("孤立", report.orphanCount)
            metric("已忽略", report.ignoredCount)
            Spacer()
            Text("共 \(report.records.count) 条合并档案")
                .font(Theme.mono(9.5)).foregroundColor(Theme.inkTertiary)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Theme.white)
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        HStack(spacing: 5) {
            Text(title).font(Theme.mono(9)).foregroundColor(Theme.inkTertiary)
            Text("\(value)").font(Theme.mono(10, .semibold)).foregroundColor(Theme.inkPrimary)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 3) {
            filterButton(.ambiguous, title: "待确认匹配", count: report.ambiguousCount)
            filterButton(.orphan, title: "孤立档案", count: report.orphanCount)
        }
        .padding(3)
        .background(Theme.warmWhite2)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
        .padding(.horizontal, 20).padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func filterButton(_ value: ArchiveReviewFilter,
                              title: String,
                              count: Int) -> some View {
        let selected = filter == value
        return Button { filter = value } label: {
            HStack(spacing: 5) {
                Text(title)
                if count > 0 { Text("\(count)").font(Theme.mono(9.5, .semibold)) }
            }
            .font(Theme.ui(11.5, selected ? .semibold : .medium))
            .foregroundColor(selected ? Theme.inkPrimary : Theme.inkSecondary)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(selected ? Theme.white : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rSM, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func recordCard(_ record: ArchiveMatchRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.archiveTitle)
                        .font(Theme.ui(13.5, .semibold)).foregroundColor(Theme.inkPrimary)
                        .lineLimit(2)
                    Text("\(record.characterCount) 字 · \(dateLabel(record.startedAt)) · \(basisLabel(record.basis))")
                        .font(Theme.mono(9.5)).foregroundColor(Theme.inkTertiary)
                }
                Spacer()
                Text(record.contentHash.prefix(10))
                    .font(Theme.mono(9)).foregroundColor(Theme.inkMuted)
            }

            if record.status == .ambiguous {
                HStack(spacing: 9) {
                    Text("绑定到")
                        .font(Theme.ui(11.5, .medium)).foregroundColor(Theme.inkSecondary)
                    Picker("会议", selection: meetingBinding(record)) {
                        ForEach(record.candidateMeetingIDs, id: \.self) { meetingID in
                            Text(meetingTitle(meetingID)).tag(meetingID)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(maxWidth: 360)
                    Spacer()
                    actionButton("确认绑定", primary: true, busy: busyRecords.contains(record.id)) {
                        let meetingID = selectedMeeting[record.id] ?? record.candidateMeetingIDs[0]
                        if store.bindArchiveRecord(record.id, to: meetingID) {
                            selectedMeeting[record.id] = nil
                        }
                    }
                }
            }

            HStack {
                Text(record.status == .ambiguous
                     ? "如果这些候选都不对，也可以明确导入为一场新会议。"
                     : "只有点击后才会创建会议、source 和提炼任务。")
                    .font(Theme.ui(10.5)).foregroundColor(Theme.inkTertiary)
                Spacer()
                actionButton("作为新会议导入", primary: record.status == .orphan,
                             busy: busyRecords.contains(record.id)) {
                    busyRecords.insert(record.id)
                    Task {
                        _ = await store.importArchiveRecordAsMeeting(record.id)
                        busyRecords.remove(record.id)
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rLG, style: .continuous))
        .hairline(Theme.borderWhisper, radius: Theme.rLG)
    }

    private func actionButton(_ title: String,
                              primary: Bool,
                              busy: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if busy { ProgressView().controlSize(.mini) }
                Text(title)
            }
            .font(Theme.ui(11.5, .semibold))
            .foregroundColor(primary ? .white : Theme.inkSecondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(primary ? AnyShapeStyle(Theme.inkGrad) : AnyShapeStyle(Theme.warmWhite2))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func meetingBinding(_ record: ArchiveMatchRecord) -> Binding<String> {
        Binding(
            get: { selectedMeeting[record.id] ?? record.candidateMeetingIDs.first ?? "" },
            set: { selectedMeeting[record.id] = $0 })
    }

    private func meetingTitle(_ id: String) -> String {
        store.meetings.first(where: { $0.id == id })?.title ?? id
    }

    private func dateLabel(_ timestamp: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    private func basisLabel(_ basis: ArchiveMatchBasis) -> String {
        switch basis {
        case .exactHash: return "全文一致"
        case .fingerprint: return "内容指纹"
        case .timeOverlap: return "时间近似"
        case .none: return "未匹配"
        case .belowMinimum: return "内容过短"
        }
    }
}
