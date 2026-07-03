import SwiftUI

/// 每日综述 — pick a day, see one digest synthesized across ALL that day's meetings (reuses the
/// generative block renderer), plus the list of meetings that fed it.
struct DailyScreen: View {
    @EnvironmentObject var store: AppStore
    @State private var day: String = ""

    private var days: [(day: String, items: [MeetingVM])] { store.meetingsByDay }
    private var current: [MeetingVM] { days.first { $0.day == day }?.items ?? [] }
    private var blocks: [NoteBlock]? { store.dailyBlocks[day] }
    private var generating: Bool { store.dailyGenerating.contains(day) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if days.isEmpty {
                    Card(padding: 0) {
                        EmptyState(icon: "sun.max", title: "还没有会可综合",
                                   message: "录几场会、或补上历史纪要后，这里按天给你一份综述。")
                    }
                } else {
                    dayChips
                    digestSection
                    meetingsSection
                }
            }
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
        .onAppear {
            if day.isEmpty { day = days.first?.day ?? "" }
            if !day.isEmpty { store.generateDigest(day: day) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Overline("跨会综合 · 当日全局", tracking: 1.2).padding(.bottom, 8)
            (Text("每日").foregroundColor(Theme.inkPrimary)
                + Text("综述").foregroundColor(Theme.accent).italic())
                .font(Theme.display(38, .medium)).tracking(-0.9)
            Text("把一天开的所有会综合成一份 digest —— 今天整体在推什么、跨会的共性、当天所有决策。")
                .font(Theme.display(15, .regular)).italic()
                .foregroundColor(Theme.inkSecondary).padding(.top, 8)
        }
    }

    private var dayChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(days, id: \.day) { d in
                    let on = d.day == day
                    Button {
                        day = d.day
                        store.generateDigest(day: d.day)
                    } label: {
                        HStack(spacing: 6) {
                            Text(d.day).font(Theme.mono(12.5, .semibold))
                            Text("\(d.items.count)").font(Theme.mono(11))
                                .foregroundColor(on ? .white.opacity(0.7) : Theme.inkTertiary)
                        }
                        .foregroundColor(on ? .white : Theme.inkSecondary)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background(on ? Theme.ink1000 : Theme.white)
                        .clipShape(Capsule())
                        .overlay { if !on { Capsule().strokeBorder(Theme.borderDefault, lineWidth: 1) } }
                    }.buttonStyle(.plain)
                }
            }
            .padding(.bottom, 2)
        }
    }

    @ViewBuilder private var digestSection: some View {
        if let b = blocks, !b.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(day) · \(current.count) 场会综述")
                        .font(Theme.display(20, .medium)).foregroundColor(Theme.inkPrimary)
                    Spacer()
                    Button { store.generateDigest(day: day, force: true) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                            Text("重新综合")
                        }.font(Theme.ui(12)).foregroundColor(Theme.inkTertiary)
                    }.buttonStyle(.plain)
                }
                NoteBlocksView(blocks: b)
            }
        } else if generating {
            Card(padding: 0) {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("正在综合当天 \(current.count) 场会…")
                        .font(Theme.ui(14)).foregroundColor(Theme.inkSecondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 44)
            }
        } else {
            Card(padding: 0) {
                VStack(spacing: 12) {
                    Text("还没生成 \(day) 的综述").font(Theme.ui(14)).foregroundColor(Theme.inkSecondary)
                    Button { store.generateDigest(day: day, force: true) } label: {
                        Text("生成综述").font(Theme.ui(13, .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 18).padding(.vertical, 9)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
                    }.buttonStyle(.plain)
                }.frame(maxWidth: .infinity).padding(.vertical, 40)
            }
        }
    }

    private var meetingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("当天的会（\(current.count)）")
                .font(Theme.display(18, .medium)).foregroundColor(Theme.inkPrimary)
            VStack(spacing: 0) {
                ForEach(Array(current.enumerated()), id: \.element.id) { idx, m in
                    Button { open(m) } label: { row(m, last: idx == current.count - 1) }
                        .buttonStyle(.plain)
                }
            }
            .background(Theme.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rLG, style: .continuous))
            .hairline(Theme.borderWhisper, radius: Theme.rLG)
            .whisperShadow()
        }
    }

    private func row(_ m: MeetingVM, last: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text(m.dayChip).font(Theme.mono(12, .semibold)).foregroundColor(Theme.accentInk)
                    .frame(width: 38, height: 38).background(Theme.accentSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(m.title).font(Theme.display(15, .medium)).foregroundColor(Theme.inkPrimary).lineLimit(1)
                    Text(m.recentMeta).font(Theme.mono(11)).foregroundColor(Theme.inkTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.inkMuted)
            }
            .padding(.vertical, 13).padding(.horizontal, 14).contentShape(Rectangle())
            if !last { Hairline() }
        }
    }

    private func open(_ m: MeetingVM) {
        if let idx = store.meetings.firstIndex(where: { $0.id == m.id }) { store.selectMeeting(idx) }
    }
}
