import SwiftUI

/// Generative meeting-note renderer. 豆包 emits an ordered list of blocks tailored to the meeting;
/// each block's sub-fields are packed into pipe-delimited strings (e.g. "label|value") — a flat
/// shape the mini model emits reliably (nested arrays-of-objects broke it ~7/8 of the time).
/// Old notes with no spec fall back to blocks synthesized from flat fields (MeetingVM.displayBlocks).
struct NoteBlocksView: View {
    let blocks: [NoteBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                block(b)
            }
        }
    }

    @ViewBuilder private func block(_ b: NoteBlock) -> some View {
        switch b.type {
        case "summary":     SummaryBlock(text: b.text ?? "")
        case "stats":       StatsBlock(items: b.items ?? [])
        case "beforeAfter": BeforeAfterBlock(before: b.before, after: b.after)
        case "keyPoints":   ListBlock(dot: Theme.brand500, title: "深度要点", lines: b.items ?? [])
        case "decisions":   DecisionsBlock(items: b.items ?? [])
        case "disputes":    DisputesBlock(items: b.items ?? [])
        case "timeline":    TimelineBlock(items: b.items ?? [])
        case "quote":       QuoteBlock(text: b.text ?? "", who: b.who)
        case "nextAgenda":  NextAgendaBlock(lines: b.items ?? [])
        default:            EmptyView()
        }
    }
}

/// Split a "a|b|c" packed string into exactly `n` trimmed parts; extra separators stay in the last
/// part (so a decision body containing "|" survives), missing parts are padded with "".
private func cut(_ s: String, _ n: Int) -> [String] {
    let raw = s.components(separatedBy: "|")
    if raw.count <= n {
        var p = raw.map { $0.trimmingCharacters(in: .whitespaces) }
        while p.count < n { p.append("") }
        return p
    }
    var p = raw.prefix(n - 1).map { $0.trimmingCharacters(in: .whitespaces) }
    p.append(raw.dropFirst(n - 1).joined(separator: "|").trimmingCharacters(in: .whitespaces))
    return p
}

// MARK: - Shared card chrome

private struct BlockCard<C: View>: View {
    let dot: Color
    let title: String
    var count: Int? = nil
    @ViewBuilder var content: () -> C

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Dot(color: dot)
                Text(title).font(Theme.display(18, .medium)).foregroundColor(Theme.inkPrimary)
                if let count { Text("\(count)").font(Theme.mono(12)).foregroundColor(Theme.inkTertiary) }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rLG, style: .continuous))
        .hairline(Theme.borderWhisper, radius: Theme.rLG)
        .whisperShadow()
    }
}

// MARK: - Blocks

private struct SummaryBlock: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.display(15.5, .regular))
            .foregroundColor(Theme.inkSecondary).lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 17).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.subtleFill)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rLG - 2, style: .continuous))
            .hairline(Theme.borderWhisper, radius: Theme.rLG - 2)
    }
}

private struct StatsBlock: View {
    let items: [String]      // "label|value"
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: 12)]
    var body: some View {
        LazyVGrid(columns: cols, alignment: .leading, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                let p = cut(it, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(p[0]).font(Theme.ui(12.5)).foregroundColor(Theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(p[1]).font(Theme.display(22, .medium)).foregroundColor(Theme.inkPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Theme.warmWhite)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
            }
        }
    }
}

private struct BeforeAfterBlock: View {
    let before: String?      // "label|detail"
    let after: String?
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            side(before, tint: Theme.inkSecondary, bg: Theme.warmWhite2, icon: "arrow.down")
            side(after, tint: Theme.green700, bg: Theme.green50, icon: "arrow.up")
        }
    }
    @ViewBuilder private func side(_ s: String?, tint: Color, bg: Color, icon: String) -> some View {
        let p = cut(s ?? "", 2)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(p[0]).font(Theme.ui(14, .medium))
            }.foregroundColor(tint)
            Text(p[1]).font(Theme.ui(12.5)).foregroundColor(Theme.inkSecondary)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
    }
}

private struct ListBlock: View {
    let dot: Color
    let title: String
    let lines: [String]
    var body: some View {
        BlockCard(dot: dot, title: title, count: lines.count) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, p in
                    HStack(alignment: .top, spacing: 12) {
                        Circle().fill(dot).frame(width: 5, height: 5).padding(.top, 8)
                        Text(p).font(Theme.ui(14)).foregroundColor(Theme.inkPrimary.opacity(0.85))
                            .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10).overlay(alignment: .top) { Hairline() }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 10).padding(.top, 6)
        }
    }
}

private struct DecisionsBlock: View {
    let items: [String]      // "no|text"
    var body: some View {
        BlockCard(dot: Theme.accent, title: "结论与决策", count: items.count) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                    let p = cut(it, 2)
                    HStack(alignment: .top, spacing: 12) {
                        Text(p[0].isEmpty ? String(format: "%02d", i + 1) : p[0])
                            .font(Theme.mono(12, .semibold)).foregroundColor(Theme.accent).padding(.top, 2)
                        Text(p[1]).font(Theme.ui(14)).foregroundColor(Theme.inkPrimary.opacity(0.85))
                            .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 11).overlay(alignment: .top) { Hairline() }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 10).padding(.top, 6)
        }
    }
}

private struct DisputesBlock: View {
    let items: [String]      // "title|body"
    var body: some View {
        BlockCard(dot: Theme.warn500, title: "分歧与未决项", count: items.count) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    let p = cut(it, 2)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(p[0]).font(Theme.ui(14, .medium)).foregroundColor(Theme.inkPrimary.opacity(0.88))
                        Text(p[1]).font(Theme.ui(13)).foregroundColor(Theme.inkSecondary)
                            .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 13).overlay(alignment: .top) { Hairline() }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 10).padding(.top, 6)
        }
    }
}

private struct TimelineBlock: View {
    let items: [String]      // "when|label|detail"
    var body: some View {
        BlockCard(dot: Theme.blue500, title: "时间线", count: items.count) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    let p = cut(it, 3)
                    HStack(alignment: .top, spacing: 12) {
                        Text(p[0]).font(Theme.mono(11, .semibold)).foregroundColor(Theme.blue600)
                            .frame(width: 54, alignment: .leading).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p[1]).font(Theme.ui(14, .medium)).foregroundColor(Theme.inkPrimary.opacity(0.88))
                            if !p[2].isEmpty {
                                Text(p[2]).font(Theme.ui(12.5)).foregroundColor(Theme.inkSecondary)
                                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 11).overlay(alignment: .top) { Hairline() }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 10).padding(.top, 6)
        }
    }
}

private struct QuoteBlock: View {
    let text: String
    let who: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("“\(text)”")
                .font(Theme.display(16, .medium))
                .foregroundColor(Theme.inkPrimary.opacity(0.9)).lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
            if let w = who, !w.isEmpty {
                Text("— \(w)").font(Theme.mono(12)).foregroundColor(Theme.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 19).padding(.vertical, 15)
        .background(Theme.subtleFill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rLG - 2, style: .continuous))
        .hairline(Theme.borderWhisper, radius: Theme.rLG - 2)
    }
}

private struct NextAgendaBlock: View {
    let lines: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Overline("下次会议建议议题", color: Theme.blue600, size: 10.5, tracking: 0.8)
            Text(lines.map { "· \($0)" }.joined(separator: "\n"))
                .font(Theme.ui(13)).foregroundColor(Theme.blue700).lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.blue50)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
    }
}

/// 完整版纪要的轻量 Markdown 渲染。覆盖 1—6 级标题、列表、引用、分隔线与常见行内格式，
/// 保持纪要阅读所需的层级感，不引入完整 Markdown/WebView 依赖。
struct MarkdownDocView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in row(for: line) }
        }
        .frame(maxWidth: 820, alignment: .leading)
    }

    /// 折叠连续空行，避免段落间距被重复的空行撑开
    private var lines: [String] {
        var out: [String] = []
        for raw in text.components(separatedBy: "\n") {
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.isEmpty, out.last?.isEmpty == true { continue }
            out.append(l)
        }
        return out
    }

    @ViewBuilder private func row(for line: String) -> some View {
        if line.isEmpty {
            Color.clear.frame(height: 5)
        } else if let heading = headingInfo(line) {
            headingRow(level: heading.level, title: heading.title)
        } else if ["---", "***", "___"].contains(line) {
            Hairline().padding(.vertical, 7)
        } else if line.hasPrefix("> ") {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5).fill(Theme.blue500.opacity(0.55)).frame(width: 3)
                inlineText(String(line.dropFirst(2)), color: Theme.inkSecondary)
            }
            .padding(.vertical, 7).padding(.horizontal, 11)
            .background(Theme.blue50.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: Theme.rSM, style: .continuous))
        } else if let checkbox = checkboxInfo(line) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: checkbox.checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(checkbox.checked ? Theme.green500 : Theme.inkMuted)
                    .padding(.top, 3)
                inlineText(checkbox.text, color: Theme.inkSecondary)
            }
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            HStack(alignment: .top, spacing: 9) {
                Circle().fill(Theme.inkMuted).frame(width: 4.5, height: 4.5).padding(.top, 7)
                inlineText(String(line.dropFirst(2)), color: Theme.inkSecondary)
            }
        } else if let range = line.range(of: #"^\d+[\.)]\s"#, options: .regularExpression) {
            HStack(alignment: .top, spacing: 9) {
                Text(String(line[..<range.upperBound]).trimmingCharacters(in: .whitespaces))
                    .font(Theme.mono(12, .medium)).foregroundColor(Theme.inkTertiary)
                    .frame(minWidth: 20, alignment: .trailing).padding(.top, 1)
                inlineText(String(line[range.upperBound...]), color: Theme.inkSecondary)
            }
        } else {
            inlineText(line, color: Theme.inkSecondary)
        }
    }

    private func headingInfo(_ line: String) -> (level: Int, title: String)? {
        let level = line.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first?.isWhitespace == true else { return nil }
        let title = rest.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : (level, title)
    }

    private func checkboxInfo(_ line: String) -> (checked: Bool, text: String)? {
        let lower = line.lowercased()
        if lower.hasPrefix("- [ ] ") { return (false, String(line.dropFirst(6))) }
        if lower.hasPrefix("- [x] ") { return (true, String(line.dropFirst(6))) }
        return nil
    }

    private func inlineText(_ value: String, color: Color) -> some View {
        Text(LocalizedStringKey(value))
            .font(Theme.ui(13.5))
            .foregroundColor(color)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func headingRow(level: Int, title: String) -> some View {
        switch level {
        case 1:
            Text(LocalizedStringKey(title))
                .font(Theme.display(22, .semibold)).tracking(-0.35)
                .foregroundColor(Theme.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2).padding(.bottom, 3)
        case 2:
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedStringKey(title))
                    .font(Theme.display(18, .semibold)).foregroundColor(Theme.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Hairline()
            }
            .padding(.top, 13).padding(.bottom, 2)
        case 3:
            Text(LocalizedStringKey(title))
                .font(Theme.ui(15.5, .semibold)).foregroundColor(Theme.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10).padding(.bottom, 1)
        case 4:
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5).fill(Theme.brand500)
                    .frame(width: 3, height: 16).padding(.top, 1)
                Text(LocalizedStringKey(title))
                    .font(Theme.ui(14.25, .semibold)).foregroundColor(Theme.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 9).padding(.bottom, 1)
        case 5:
            Text(LocalizedStringKey(title))
                .font(Theme.ui(13.5, .semibold)).foregroundColor(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)
        default:
            Text(LocalizedStringKey(title))
                .font(Theme.ui(12.5, .semibold)).foregroundColor(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }
}
