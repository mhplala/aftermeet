import SwiftUI

struct KnowledgeInboxView: View {
    @EnvironmentObject var store: AppStore

    private var items: [KnowledgeInboxItem] { store.visibleKnowledgeInboxItems }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            stateFilters
            secondaryFilters
            if items.isEmpty {
                Card(padding: 0) {
                    EmptyState(
                        icon: "line.3.horizontal.decrease.circle",
                        title: "当前筛选下没有内容",
                        message: "可以切换状态、类型、来源或时间范围。")
                }
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(items) { item in
                        candidateCard(item)
                    }
                }
            }
        }
    }

    private var stateFilters: some View {
        HStack(spacing: 3) {
            stateButton(.pending, "待确认")
            stateButton(.conflicts, "冲突")
            stateButton(.missingOwner, "缺负责人")
            stateButton(.duplicates, "疑似重复")
            stateButton(.processed, "已处理")
        }
        .padding(3)
        .background(Theme.warmWhite2)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous)
            .strokeBorder(Theme.borderWhisper, lineWidth: 1))
    }

    private func stateButton(_ filter: KnowledgeInboxFilter, _ title: String) -> some View {
        let selected = store.knowledgeInboxFilter == filter
        let count = store.knowledgeInboxCount(filter)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { store.knowledgeInboxFilter = filter }
        } label: {
            HStack(spacing: 5) {
                Text(title)
                if count > 0 {
                    Text("\(count)")
                        .font(Theme.mono(9.5, .semibold))
                        .foregroundColor(selected ? Theme.inkPrimary : Theme.inkTertiary)
                }
            }
            .font(Theme.ui(11.5, selected ? .semibold : .medium))
            .foregroundColor(selected ? Theme.inkPrimary : Theme.inkSecondary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(selected ? Theme.white : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rSM, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var secondaryFilters: some View {
        HStack(spacing: 8) {
            picker("类型", selection: $store.knowledgeKindFilter) {
                Text("全部类型").tag(nil as KnowledgeKind?)
                ForEach(KnowledgeKind.allCases, id: \.rawValue) { kind in
                    Text(kindLabel(kind)).tag(Optional(kind))
                }
            }
            picker("来源", selection: $store.knowledgeSourceFilter) {
                Text("全部来源").tag(nil as KnowledgeSourceKind?)
                ForEach(KnowledgeSourceKind.allCases, id: \.rawValue) { source in
                    Text(sourceLabel(source)).tag(Optional(source))
                }
            }
            picker("时间", selection: $store.knowledgeDateFilter) {
                Text("全部时间").tag(KnowledgeDateFilter.all)
                Text("最近 7 天").tag(KnowledgeDateFilter.last7Days)
                Text("最近 30 天").tag(KnowledgeDateFilter.last30Days)
                Text("最近 90 天").tag(KnowledgeDateFilter.last90Days)
            }
            Spacer()
            Text("\(items.count) 条")
                .font(Theme.mono(10.5)).foregroundColor(Theme.inkTertiary)
        }
    }

    private func picker<Selection: Hashable, Content: View>(
        _ title: String,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Picker(title, selection: selection, content: content)
            .labelsHidden()
            .pickerStyle(.menu)
            .font(Theme.ui(11.5, .medium))
            .frame(minWidth: 104)
    }

    private func candidateCard(_ item: KnowledgeInboxItem) -> some View {
        let primaryEvidence = item.evidenceContexts.first(where: { $0.link.evidenceRole == .support })
            ?? item.evidenceContexts.first
        let projects = projectLabels(item)
        return VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 7) {
                Text(kindLabel(item.unit.kind))
                    .font(Theme.mono(9.5, .semibold))
                    .foregroundColor(Theme.inkSecondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Theme.warmWhite2)
                    .clipShape(Capsule())
                Text(item.unit.evidenceLevel == .direct ? "直接证据" : "推断")
                    .font(Theme.mono(9.5, .semibold))
                    .foregroundColor(item.unit.evidenceLevel == .direct ? Theme.green700 : Theme.warn500)
                if item.unit.sensitivity == .restricted {
                    Text("敏感")
                        .font(Theme.mono(9.5, .semibold)).foregroundColor(Theme.warn500)
                }
                if item.duplicateCount > 1 {
                    Text("疑似重复 \(item.duplicateCount)")
                        .font(Theme.mono(9.5, .semibold)).foregroundColor(Theme.warn500)
                }
                Spacer()
                Text(dateLabel(item.unit.observedAt))
                    .font(Theme.mono(9.5)).foregroundColor(Theme.inkTertiary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.inkMuted)
            }

            Text(item.unit.canonicalText)
                .font(Theme.ui(14, .medium)).foregroundColor(Theme.inkPrimary)
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)

            let attributes = structuredAttributes(item.unit)
            if !attributes.isEmpty {
                HStack(spacing: 7) {
                    ForEach(attributes, id: \.self) { value in
                        Text(value)
                            .font(Theme.mono(9.5)).foregroundColor(Theme.inkSecondary)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.warmWhite)
                            .clipShape(Capsule())
                    }
                }
            }

            if !projects.isEmpty {
                HStack(spacing: 6) {
                    Text("项目建议").font(Theme.mono(9)).foregroundColor(Theme.inkTertiary)
                    ForEach(projects, id: \.self) { project in
                        Text(project)
                            .font(Theme.ui(10.5, .medium)).foregroundColor(Theme.inkSecondary)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.warmWhite2).clipShape(Capsule())
                    }
                }
            }

            if let evidence = primaryEvidence {
                VStack(alignment: .leading, spacing: 7) {
                    Text("“\(evidence.link.quote)”")
                        .font(Theme.ui(12.5)).foregroundColor(Theme.inkSecondary)
                        .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    Text(evidenceMeta(evidence))
                        .font(Theme.mono(9.5)).foregroundColor(Theme.inkTertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.warmWhite)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rSM, style: .continuous))
            } else {
                Text("证据索引缺失，这条候选不能确认")
                    .font(Theme.ui(11.5, .medium)).foregroundColor(Theme.danger500)
            }

            HStack(spacing: 8) {
                if let evidence = primaryEvidence {
                    Button {
                        store.openKnowledgeEvidence(evidence)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "quote.bubble").font(.system(size: 10))
                            Text("查看上下文")
                        }
                        .font(Theme.ui(11.5, .semibold)).foregroundColor(Theme.inkSecondary)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(Theme.warmWhite2).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if item.duplicateCount > 1 && item.unit.reviewStatus != .rejected {
                    Button {
                        store.beginDuplicateReview(item)
                    } label: {
                        Text("处理重复")
                            .font(Theme.ui(11.5, .semibold)).foregroundColor(Theme.warn500)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Theme.warn50).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if item.unit.conflictStatus == .pending && item.unit.reviewStatus != .rejected {
                    Button {
                        store.beginConflictReview(item)
                    } label: {
                        Text("处理冲突")
                            .font(Theme.ui(11.5, .semibold)).foregroundColor(Theme.warn500)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Theme.warn50).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                if item.unit.reviewStatus != .rejected {
                    Button {
                        store.beginEditingKnowledgeUnit(item)
                    } label: {
                        Text("编辑")
                            .font(Theme.ui(11.5, .semibold)).foregroundColor(Theme.inkSecondary)
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(Theme.warmWhite2).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Button {
                        store.rejectKnowledgeUnit(id: item.unit.id)
                    } label: {
                        Text("忽略")
                            .font(Theme.ui(11.5, .semibold)).foregroundColor(Theme.inkTertiary)
                            .padding(.horizontal, 9).padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if item.unit.reviewStatus == .candidate {
                    Button {
                        store.confirmKnowledgeUnit(id: item.unit.id)
                    } label: {
                        Text("确认")
                            .font(Theme.ui(11.5, .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(primaryEvidence == nil
                                        ? AnyShapeStyle(Theme.inkMuted)
                                        : AnyShapeStyle(Theme.inkGrad))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(primaryEvidence == nil)
                } else if item.unit.reviewStatus == .rejected {
                    Button {
                        store.restoreKnowledgeUnit(id: item.unit.id)
                    } label: {
                        Text("恢复")
                            .font(Theme.ui(11.5, .semibold)).foregroundColor(Theme.inkSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Theme.warmWhite2).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("已确认")
                        .font(Theme.mono(10, .semibold)).foregroundColor(Theme.inkTertiary)
                }
            }
        }
        .padding(17)
        .background(Theme.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rLG, style: .continuous))
        .hairline(Theme.borderWhisper, radius: Theme.rLG)
        .whisperShadow()
    }

    private func structuredAttributes(_ unit: KnowledgeUnit) -> [String] {
        var values: [String] = []
        if let owner = unit.owner { values.append("负责人 · \(owner)") }
        if let due = unit.dueText { values.append("时间 · \(due)") }
        if let number = unit.numericValue {
            values.append("数值 · \(String(format: "%g", number))\(unit.valueUnit ?? "")")
        }
        return values
    }

    private func projectLabels(_ item: KnowledgeInboxItem) -> [String] {
        let byID = Dictionary(uniqueKeysWithValues: store.knowledgeProjects.map { ($0.id, $0.name) })
        let linked = item.projectLinks.compactMap { byID[$0.projectID] }
        if !linked.isEmpty { return linked }
        guard let data = item.unit.payloadJSON.data(using: .utf8),
              let candidate = try? JSONDecoder().decode(KnowledgeExtractionCandidate.self, from: data)
        else { return [] }
        return candidate.projectHints
    }

    private func evidenceMeta(_ evidence: KnowledgeInboxEvidence) -> String {
        let meetingTitle = store.meetings.first(where: { $0.id == evidence.source.meetingID })?.title
            ?? evidence.source.meetingID
        let speaker = evidence.segment.speaker.map { " · \($0)" } ?? ""
        let position: String
        if let start = evidence.segment.startMS {
            position = " · \(relativeTime(start))"
        } else {
            position = " · 字符 \(evidence.segment.charStart)–\(evidence.segment.charEnd)"
        }
        return meetingTitle + speaker + position
    }

    private func relativeTime(_ milliseconds: Int) -> String {
        let seconds = max(0, milliseconds / 1_000)
        if seconds >= 3_600 {
            return String(format: "%d:%02d:%02d", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func kindLabel(_ kind: KnowledgeKind) -> String {
        switch kind {
        case .fact: return "事实"
        case .decision: return "决策"
        case .action: return "行动"
        case .openQuestion: return "未决"
        case .metric: return "指标"
        case .risk: return "风险"
        case .dispute: return "分歧"
        }
    }

    private func sourceLabel(_ source: KnowledgeSourceKind) -> String {
        switch source {
        case .liveCloud: return "云端转写"
        case .liveLocal: return "本地转写"
        case .feishu: return "飞书"
        case .archive: return "历史档案"
        }
    }

    private func dateLabel(_ timestamp: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}
