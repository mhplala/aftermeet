import SwiftUI

struct KnowledgeUnitEditorView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let item: KnowledgeInboxItem

    @State private var canonicalText: String
    @State private var subject: String
    @State private var predicate: String
    @State private var objectText: String
    @State private var numericValue: String
    @State private var valueUnit: String
    @State private var owner: String
    @State private var dueText: String

    init(item: KnowledgeInboxItem) {
        self.item = item
        _canonicalText = State(initialValue: item.unit.canonicalText)
        _subject = State(initialValue: item.unit.subject ?? "")
        _predicate = State(initialValue: item.unit.predicate ?? "")
        _objectText = State(initialValue: item.unit.objectText ?? "")
        _numericValue = State(initialValue: item.unit.numericValue.map { String(format: "%g", $0) } ?? "")
        _valueUnit = State(initialValue: item.unit.valueUnit ?? "")
        _owner = State(initialValue: item.unit.owner ?? "")
        _dueText = State(initialValue: item.unit.dueText ?? "")
    }

    private var parsedNumber: Double? {
        let value = numericValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : Double(value)
    }

    private var numberIsValid: Bool {
        numericValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || parsedNumber?.isFinite == true
    }

    private var canSave: Bool {
        !canonicalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && numberIsValid
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    fieldLabel("知识表述")
                    TextEditor(text: $canonicalText)
                        .font(Theme.ui(13.5))
                        .foregroundColor(Theme.inkPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 88)
                        .background(Theme.warmWhite)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
                        .hairline(Theme.borderDefault, radius: Theme.rMD)

                    fieldLabel("结构化字段")
                    VStack(spacing: 0) {
                        fieldRow("主体", text: $subject, placeholder: "可留空")
                        Hairline()
                        fieldRow("关系", text: $predicate, placeholder: "可留空")
                        Hairline()
                        fieldRow("对象", text: $objectText, placeholder: "可留空")
                        Hairline()
                        fieldRow("负责人", text: $owner, placeholder: "原文未明确则留空")
                        Hairline()
                        fieldRow("时间", text: $dueText, placeholder: "原文未明确则留空")
                        Hairline()
                        HStack(spacing: 10) {
                            Text("数值").font(Theme.ui(12)).foregroundColor(Theme.inkSecondary)
                                .frame(width: 72, alignment: .leading)
                            TextField("可留空", text: $numericValue)
                                .textFieldStyle(.plain).font(Theme.mono(12))
                            TextField("单位", text: $valueUnit)
                                .textFieldStyle(.plain).font(Theme.mono(12))
                                .frame(width: 90)
                        }
                        .padding(.horizontal, 13).padding(.vertical, 11)
                    }
                    .background(Theme.white)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
                    .hairline(numberIsValid ? Theme.borderWhisper : Theme.danger500, radius: Theme.rMD)

                    fieldLabel("原文证据 · 不可编辑")
                    if let evidence = item.evidenceContexts.first(where: { $0.link.evidenceRole == .support })
                        ?? item.evidenceContexts.first {
                        Text("“\(evidence.link.quote)”")
                            .font(Theme.ui(12.5)).foregroundColor(Theme.inkSecondary)
                            .lineSpacing(3).textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.warmWhite)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.rSM, style: .continuous))
                    }
                }
                .padding(22)
            }
            Hairline()
            footer
        }
        .frame(width: 620, height: 620)
        .background(Theme.canvas)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("编辑知识")
                    .font(Theme.display(15, .semibold)).foregroundColor(Theme.inkPrimary)
                Text("保存后成为已编辑版本，原始证据不会改变")
                    .font(Theme.mono(9.5)).foregroundColor(Theme.inkTertiary)
            }
            Spacer()
            Text("rev \(item.unit.revision + 1)")
                .font(Theme.mono(9.5, .semibold)).foregroundColor(Theme.inkTertiary)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(Theme.white)
    }

    private var footer: some View {
        HStack {
            if !numberIsValid {
                Text("数值格式无效")
                    .font(Theme.ui(11, .medium)).foregroundColor(Theme.danger500)
            }
            Spacer()
            Button("取消") { dismiss() }
                .buttonStyle(.plain)
                .font(Theme.ui(11.5, .semibold)).foregroundColor(Theme.inkSecondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
            Button {
                let edits = KnowledgeUnitEdits(
                    canonicalText: canonicalText,
                    subject: nilIfEmpty(subject),
                    predicate: nilIfEmpty(predicate),
                    objectText: nilIfEmpty(objectText),
                    numericValue: parsedNumber,
                    valueUnit: nilIfEmpty(valueUnit),
                    owner: nilIfEmpty(owner),
                    dueText: nilIfEmpty(dueText),
                    validFrom: item.unit.validFrom,
                    validTo: item.unit.validTo)
                if store.editKnowledgeUnit(id: item.id, edits: edits) { dismiss() }
            } label: {
                Text("保存并确认")
                    .font(Theme.ui(11.5, .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(canSave ? AnyShapeStyle(Theme.inkGrad) : AnyShapeStyle(Theme.inkMuted))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(.horizontal, 18).padding(.vertical, 13)
        .background(Theme.white)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(9.5, .semibold)).tracking(0.7)
            .foregroundColor(Theme.inkTertiary)
            .textCase(.uppercase)
    }

    private func fieldRow(_ label: String,
                          text: Binding<String>,
                          placeholder: String) -> some View {
        HStack(spacing: 10) {
            Text(label).font(Theme.ui(12)).foregroundColor(Theme.inkSecondary)
                .frame(width: 72, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain).font(Theme.ui(12.5)).foregroundColor(Theme.inkPrimary)
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
    }

    private func nilIfEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
