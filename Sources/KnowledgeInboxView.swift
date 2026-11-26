import SwiftUI

struct KnowledgeInboxView: View {
    @EnvironmentObject var store: AppStore

    private var items: [KnowledgeInboxItem] { store.visibleKnowledgeInboxItems }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            trustBoundary
            let legacyCount = store.knowledgeInboxItems.filter { $0.unit.topicContext == nil && $0.unit.reviewStatus == .candidate }.count
            if legacyCount > 0 {
                Toggle("显示旧版片段（\(legacyCount) 条，尚未按话题重新提炼）", isOn: $store.showLegacyKnowledgeFragments)
                    .font(Theme.ui(11.5)).foregroundColor(Theme.inkSecondary)
            }
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

    private var trustBoundary: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.inkSecondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("这里是候选，不是知识")
                    .font(Theme.ui(12.5, .semibold)).foregroundColor(Theme.inkPrimary)
                Text("按整场讨论沉淀关键事实、决策依据和适用范围；普通排期与进度不进入知识库。每项内容都要有原文支持，核对通过后仍需你确认。")
                    .font(Theme.ui(11.5)).foregroundColor(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(13)
        .background(Theme.warmWhite)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
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
        let canConfirm = primaryEvidence != nil && item.unit.verificationStatus == .passed
        let projects = projectLabels(item)
        return VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 7) {
                Text(verificationStatusLabel(item.unit))
                    .font(Theme.mono(9.5, .semibold))
                    .foregroundColor(item.unit.verificationStatus == .passed ? Theme.green700 : Theme.warn500)
                Text(kindLabel(item.unit.kind))
                    .font(Theme.mono(9.5, .semibold))
                    .foregroundColor(Theme.inkSecondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Theme.warmWhite2)
                    .clipShape(Capsule())
                Text(claimTypeLabel(item.unit.claimType))
                    .font(Theme.mono(9.5, .semibold)).foregroundColor(Theme.inkSecondary)
                if item.unit.epistemicStatus != .certain {
                    Text(epistemicLabel(item.unit.epistemicStatus))
                        .font(Theme.mono(9.5, .semibold)).foregroundColor(Theme.warn500)
                }
                Text(item.unit.evidenceLevel == .direct ? "直接证据" : (item.unit.topicContext == nil ? "推断" : "多段归纳"))
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
                if let context = item.unit.topicContext {
                    KnowledgeTopicContextView(context: context, evidence: item.evidenceContexts)
                    Text(evidenceMeta(evidence)).font(Theme.ui(10.5)).foregroundColor(Theme.inkTertiary)
                } else {
                    Text("旧版片段 · 需要按整场话题重新提炼").font(Theme.ui(11, .medium)).foregroundColor(Theme.warn500)
                    KnowledgeMeetingContext(source: evidence.source)
                }

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

            if item.unit.verificationStatus != .passed {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.unit.verificationStatus == .pending ? "等待语义验证" : "验证未通过")
                        .font(Theme.ui(11.5, .semibold)).foregroundColor(Theme.warn500)
                    ForEach(item.unit.verificationReasons, id: \.self) { reason in
                        Text("· " + blockerLabel(reason))
                            .font(Theme.ui(11)).foregroundColor(Theme.inkSecondary)
                    }
                    if item.unit.verificationReasons.isEmpty {
                        Text("这条候选需要重新核对后才能确认。")
                            .font(Theme.ui(11)).foregroundColor(Theme.inkSecondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.warn50)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rSM, style: .continuous))
            }

            HStack(spacing: 8) {
                if let evidence = primaryEvidence {
                    Button {
                        store.openKnowledgeEvidence(evidence)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "quote.bubble").font(.system(size: 10))
                            Text("查看会议与知识上下文")
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
                            .background(canConfirm
                                        ? AnyShapeStyle(Theme.inkGrad)
                                        : AnyShapeStyle(Theme.inkMuted))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canConfirm)
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

    private func verificationStatusLabel(_ unit: KnowledgeUnit) -> String {
        if unit.reviewStatus == .rejected { return "已忽略" }
        if unit.isTrusted { return unit.reviewStatus == .edited ? "人工修订" : "已确认" }
        switch unit.verificationStatus {
        case .pending: return "待验证"
        case .passed: return "可确认"
        case .blocked: return "需修正"
        }
    }

    private func claimTypeLabel(_ value: KnowledgeClaimType) -> String {
        switch value {
        case .observedFact: return "事实主张"
        case .attributedOpinion: return "归属意见"
        case .forecast: return "预测"
        case .proposal: return "提议"
        case .decision: return "决定"
        case .commitment: return "承诺"
        case .statusUpdate: return "状态更新"
        case .openQuestion: return "问题"
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

    private func blockerLabel(_ value: String) -> String {
        switch value {
        case KnowledgeQualificationIssue.missingTopicContext.rawValue: return "话题缺少背景、关键事实或决策依据"
        case KnowledgeQualificationIssue.transientTopic.rawValue: return "普通排期与进度不应作为知识"
        case KnowledgeQualificationIssue.invalidContextEvidence.rawValue: return "上下文内容缺少有效原文关联"

        case KnowledgeQualificationIssue.inferredClaim.rawValue: return "主张仍依赖推断"
        case KnowledgeQualificationIssue.incompatibleClaimType.rawValue: return "主张性质与知识类型冲突"
        case KnowledgeQualificationIssue.missingOwner.rawValue: return "承诺缺少明确负责人"
        case KnowledgeQualificationIssue.missingAttribution.rawValue: return "意见、预测或承诺缺少明确归属人"
        case KnowledgeQualificationIssue.unresolvedReference.rawValue: return "存在未解析的指代"
        case KnowledgeQualificationIssue.vaguePredicate.rawValue: return "关系字段过于模糊"
        case KnowledgeQualificationIssue.multiplePropositions.rawValue: return "一条候选混合了多个命题"
        case KnowledgeQualificationIssue.speechActMismatch.rawValue: return "疑问、提议、承诺或状态被错误归类"
        case KnowledgeQualificationIssue.modalityStrengthened.rawValue: return "候选强化了原文的不确定语气"
        case KnowledgeQualificationIssue.semanticUncertain.rawValue: return "原文不足以确定这条主张"
        case KnowledgeQualificationIssue.semanticUnsupported.rawValue: return "原文不支持这条主张或其中字段"
        case KnowledgeQualificationIssue.requiresVerifierUpgrade.rawValue: return "这条候选尚未完成完整核对"
        case "missing_support": return "缺少可用的原文支持"
        case KnowledgeQualificationIssue.supersededExtraction.rawValue: return "已被更新后的候选替代"
        default: return "需要人工核对"
        }
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
