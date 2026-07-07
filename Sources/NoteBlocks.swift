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
            .background(Color(hex: "fafafa"))
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
        .background(Color(hex: "fafafa"))
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
