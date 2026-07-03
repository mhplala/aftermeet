import SwiftUI

struct TranscriptFile: Identifiable {
    let id = UUID()
    let url: URL          // first fragment (for "reveal in Finder")
    let title: String
    let chars: Int
    let preview: String
    let body: String
}

struct HistoryScreen: View {
    @State private var files: [TranscriptFile] = []
    @State private var selected: TranscriptFile?

    static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AfterMeet/transcripts")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let sel = selected { detail(sel) } else { list }
            }
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
        .onAppear(perform: load)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            Overline("会中转写 · 本地存档", tracking: 1.2).padding(.bottom, 8)
            Text("转写历史")
                .font(Theme.display(38, .medium)).tracking(-0.9).foregroundColor(Theme.inkPrimary)
            Text("同一场会的碎片(间隔 <12 分钟)自动合并成一条。点开看全文。")
                .font(Theme.display(15, .regular)).italic()
                .foregroundColor(Theme.inkSecondary).padding(.top, 8).padding(.bottom, 24)

            if files.isEmpty {
                Card(padding: 0) {
                    EmptyState(icon: "doc.text", title: "还没有转写记录",
                               message: "去「会中转写」录一场,文字会实时存到这里。")
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(files.enumerated()), id: \.element.id) { idx, f in
                        Button { selected = f } label: { row(f, last: idx == files.count - 1) }
                            .buttonStyle(.plain)
                    }
                }
                .background(Theme.white)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rLG, style: .continuous))
                .hairline(Theme.borderWhisper, radius: Theme.rLG)
                .whisperShadow()
            }
        }
    }

    private func row(_ f: TranscriptFile, last: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous).fill(Theme.accentSurface).frame(width: 38, height: 38)
                    Image(systemName: "waveform").font(.system(size: 16)).foregroundColor(Theme.accentInk)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(f.title).font(Theme.display(15, .medium)).foregroundColor(Theme.inkPrimary)
                        Text("\(f.chars) 字").font(Theme.mono(10.5)).foregroundColor(Theme.inkTertiary)
                    }
                    Text(f.preview).font(Theme.ui(12.5)).foregroundColor(Theme.inkSecondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.inkMuted).padding(.top, 4)
            }
            .padding(.vertical, 15).padding(.horizontal, 20)
            .contentShape(Rectangle())
            if !last { Hairline() }
        }
    }

    private func detail(_ f: TranscriptFile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { selected = nil } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                    Text("转写历史").font(Theme.ui(13))
                }.foregroundColor(Theme.blue500)
            }.buttonStyle(.plain).padding(.bottom, 14)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(f.title).font(Theme.display(26, .medium)).tracking(-0.4).foregroundColor(Theme.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button { NSWorkspace.shared.activateFileViewerSelecting([f.url]) } label: {
                    Text("在访达中显示").font(Theme.ui(12.5, .semibold)).foregroundColor(Theme.inkPrimary.opacity(0.85))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.white).clipShape(RoundedRectangle(cornerRadius: Theme.rSM, style: .continuous))
                        .hairline(Theme.borderDefault, radius: Theme.rSM)
                }.buttonStyle(.plain)
            }
            .padding(.bottom, 6)
            Text("\(f.chars) 字").font(Theme.mono(12)).foregroundColor(Theme.inkTertiary).padding(.bottom, 18)

            Card(padding: 22) {
                Text(f.body)
                    .font(Theme.ui(14)).foregroundColor(Theme.inkPrimary.opacity(0.88))
                    .lineSpacing(6).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: load + merge contiguous fragments

    private struct Frag { let url: URL; let start: Date; let end: Date; let name: String; let dateStr: String; let body: String }

    private func load() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let dd = DateFormatter(); dd.locale = Locale(identifier: "zh_CN"); dd.dateFormat = "M月d日 HH:mm"

        let frags: [Frag] = urls.filter { $0.pathExtension == "txt" }.compactMap { url in
            let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let lines = raw.components(separatedBy: "\n")
            let header = (lines.first ?? "").replacingOccurrences(of: "# ", with: "")
            let name = header.components(separatedBy: " · ").first?.trimmingCharacters(in: .whitespaces) ?? ""
            let body = lines.dropFirst().filter { !$0.isEmpty }.joined(separator: "\n")
            let start = startFromFilename(url) ?? .distantPast
            let end = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? start
            return Frag(url: url, start: start, end: end, name: name, dateStr: dd.string(from: start), body: body)
        }.sorted { $0.start < $1.start }

        // group by contiguity: gap between a fragment's start and the running group's last end < 12 min
        var groups: [[Frag]] = []
        for f in frags {
            if let last = groups.last?.last, f.start.timeIntervalSince(last.end) < 12 * 60 {
                groups[groups.count - 1].append(f)
            } else { groups.append([f]) }
        }

        let tf = DateFormatter(); tf.dateFormat = "HH:mm"
        let generic: (String) -> Bool = { $0.isEmpty || $0 == "未命名会议" || $0 == "会中实时转写" }
        files = groups.map { g -> TranscriptFile in
            // name from the largest non-generic fragment — most representative, usually the 豆包 content name
            let name = g.filter { !generic($0.name) }.max(by: { $0.body.count < $1.body.count })?.name ?? "未命名会议"
            let body = g.map { $0.body }.joined(separator: "\n")
            let dayPart = g.first!.dateStr.components(separatedBy: " ").first ?? ""
            let span = "\(tf.string(from: g.first!.start))–\(tf.string(from: g.last!.end))"
            let title = g.count > 1
                ? "\(name) · \(dayPart) \(span)（\(g.count) 段合并）"
                : "\(name) · \(g.first!.dateStr)"
            return TranscriptFile(url: g.first!.url, title: title, chars: body.count,
                                  preview: String(body.replacingOccurrences(of: "\n", with: " ").prefix(90)),
                                  body: body)
        }.reversed()
    }

    private func startFromFilename(_ url: URL) -> Date? {
        let s = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "会中转写-", with: "")
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd-HHmmss"; df.timeZone = .current
        return df.date(from: s)
    }
}
