import SwiftUI

struct FollowupScreen: View {
    @EnvironmentObject var store: AppStore

    private var cards: [AppStore.RecurringCard] { store.recurringCards }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Overline("会前 · 自动追问", tracking: 1.2).padding(.bottom, 8)
                Text("进度追问卡")
                    .font(Theme.display(36, .semibold)).tracking(-0.8).foregroundColor(Theme.inkPrimary)
                Text(subtitle)
                    .font(Theme.display(15, .regular))
                    .foregroundColor(Theme.inkSecondary)
                    .padding(.top, 8).padding(.bottom, 24)
                    .fixedSize(horizontal: false, vertical: true)

                if store.usingRealData {
                    if cards.isEmpty {
                        Card(padding: 0) {
                            EmptyState(icon: "clock.arrow.circlepath",
                                       title: "暂无周期性会议",
                                       message: "当日历中出现同主题会议的下一场时，\n这里会自动生成上次待办的进度汇总。")
                        }
                    } else {
                        ForEach(Array(cards.enumerated()), id: \.element.title) { idx, card in
                            RecurringCardView(card: card)
                                .padding(.bottom, idx == cards.count - 1 ? 0 : 20)
                        }
                    }
                } else {
                    SampleFollowCard()
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
    }

    private var subtitle: String {
        if store.usingRealData {
            return cards.count > 1
                ? "接下来 7 天有 \(cards.count) 场周期性会议，各自的上次待办进度已汇总。"
                : "同主题会议再次召开前，这里会自动汇总上一场待办的完成情况。"
        }
        return "「产品周例会」开始前，已汇总上次待办的完成进度。"
    }
}

// MARK: - 单张追问卡（真实数据）

struct RecurringCardView: View {
    @EnvironmentObject var store: AppStore
    let card: AppStore.RecurringCard
    @State private var showForward = false

    private var doneN: Int { card.items.filter { $0.done }.count }
    private var notDoneN: Int { card.items.filter { !$0.done }.count }
    private var rate: Int { card.items.isEmpty ? 0 : Int((Double(doneN) / Double(card.items.count) * 100).rounded()) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            statRow
            Hairline()
            items
            footer
        }
        .background(Theme.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rXL, style: .continuous))
        .hairline(Theme.borderDefault, radius: Theme.rXL)
        .cardShadow()
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous)
                    .fill(Theme.warmWhite2).frame(width: 40, height: 40)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18, weight: .regular)).foregroundColor(Theme.green500)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("「\(card.title)」" + (card.upcomingLabel.map { "将于 \($0) 举行" } ?? "的待办进度"))
                    .font(Theme.display(16, .medium)).foregroundColor(Theme.inkPrimary)
                    .lineLimit(1)
                Text("上一场：\(card.prevMeta)").font(Theme.mono(11)).foregroundColor(Theme.inkTertiary)
            }
            Spacer()
            if let date = card.upcomingDate {
                Button { Lark.openCalendar(at: date) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar").font(.system(size: 11))
                        Text("日历").font(Theme.ui(12, .semibold))
                    }
                    .foregroundColor(Theme.blue700)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Theme.blue50).clipShape(Capsule())
                    .contentShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 17)
    }

    private var statRow: some View {
        HStack(spacing: 14) {
            statBox(value: "\(doneN)", label: "已完成", bg: Theme.green50, fg: Theme.green700)
            statBox(value: "\(notDoneN)", label: "未完成", bg: Theme.danger50, fg: Theme.danger500)
            statBox(value: "\(rate)", unit: "%", label: "闭环率", bg: Theme.warmWhite, fg: Theme.inkPrimary,
                    labelFg: Theme.inkSecondary)
        }
        .padding(.horizontal, 22).padding(.vertical, 18)
    }

    private func statBox(value: String, unit: String? = nil, label: String,
                         bg: Color, fg: Color, labelFg: Color? = nil) -> some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value).font(Theme.display(32, .semibold)).foregroundColor(fg)
                if let unit { Text(unit).font(Theme.display(17, .medium)).foregroundColor(fg) }
            }
            Text(label).font(Theme.ui(12, .medium)).foregroundColor(labelFg ?? fg)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
    }

    private var items: some View {
        VStack(spacing: 0) {
            ForEach(Array(card.items.enumerated()), id: \.element.id) { idx, f in
                Button { store.toggleFollowItem(text: f.text, meetingTitle: card.prevTitle) } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            mark(done: f.done)
                            Text(f.text)
                                .font(Theme.ui(13.5))
                                .foregroundColor(f.done ? Theme.inkTertiary : Theme.inkPrimary.opacity(0.85))
                            Spacer()
                            Text(f.owner).font(Theme.ui(12)).foregroundColor(Theme.inkSecondary)
                            Text(f.done ? "已完成" : "未完成")
                                .font(Theme.ui(11, .semibold))
                                .foregroundColor(f.done ? Theme.green700 : Theme.danger500)
                                .frame(width: 62)
                                .padding(.vertical, 3)
                                .background(f.done ? Theme.green50 : Theme.danger50)
                                .clipShape(Capsule())
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        if idx != card.items.count - 1 { Hairline() }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22).padding(.top, 4).padding(.bottom, 10)
    }

    private func mark(done: Bool) -> some View {
        ZStack {
            Circle().fill(done ? Theme.green500 : Color.clear).frame(width: 18, height: 18)
                .overlay { if !done { Circle().strokeBorder(Theme.danger500.opacity(0.5), lineWidth: 1.5) } }
            if done {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundColor(.white)
            } else {
                Circle().fill(Theme.danger500).frame(width: 6, height: 6)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("转发到群后，将 @ 未完成项的负责人。")
                .font(Theme.ui(12.5)).foregroundColor(Theme.inkSecondary)
            Spacer()
            Button { store.showToast("已存为草稿") } label: {
                Text("存为草稿").font(Theme.ui(13, .semibold)).foregroundColor(Theme.inkPrimary.opacity(0.85))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Theme.white)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Theme.borderDefault, lineWidth: 1))
                    .contentShape(Capsule())
            }.buttonStyle(.plain).fixedSize()
            Button { showForward = true } label: {
                Text("发到会议群").font(Theme.ui(13, .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Theme.inkGrad)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain).fixedSize()
            .popover(isPresented: $showForward, arrowEdge: .top) {
                ForwardPicker(meetingTitle: card.title,
                              copyMarkdown: AppStore.followupMarkdown(card)) { chat in
                    showForward = false
                    store.send(markdown: AppStore.followupMarkdown(card), to: chat, what: "进度追问卡")
                }
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 15)
        .background(Theme.warmWhite)
    }
}

// MARK: - 示例卡（零数据演示）

struct SampleFollowCard: View {
    @EnvironmentObject var store: AppStore

    private var doneN: Int { store.fitems.filter { $0.done }.count }
    private var rate: Int { store.fitems.isEmpty ? 0 : Int((Double(doneN) / Double(store.fitems.count) * 100).rounded()) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous)
                        .fill(Theme.warmWhite2).frame(width: 40, height: 40)
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 18)).foregroundColor(Theme.green500)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("上次「产品周例会」的待办进度")
                        .font(Theme.display(16, .medium)).foregroundColor(Theme.inkPrimary)
                    Text("6月3日 周二 · 6 条待办").font(Theme.mono(11)).foregroundColor(Theme.inkTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 22).padding(.vertical, 17)
            Hairline()
            HStack(spacing: 14) {
                sBox("\(doneN)", "已完成", Theme.green50, Theme.green700)
                sBox("\(store.fitems.count - doneN)", "未完成", Theme.danger50, Theme.danger500)
                sBox("\(rate)%", "闭环率", Theme.warmWhite, Theme.inkPrimary)
            }
            .padding(.horizontal, 22).padding(.vertical, 18)
            Hairline()
            VStack(spacing: 0) {
                ForEach(Array(store.fitems.enumerated()), id: \.element.id) { idx, f in
                    Button { store.toggleFitem(f.id) } label: {
                        HStack(spacing: 12) {
                            Circle().fill(f.done ? Theme.green500 : Theme.danger50).frame(width: 16, height: 16)
                            Text(f.text).font(Theme.ui(13.5))
                                .foregroundColor(f.done ? Theme.inkTertiary : Theme.inkPrimary.opacity(0.85))
                            Spacer()
                            Text(f.owner).font(Theme.ui(12)).foregroundColor(Theme.inkSecondary)
                        }
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if idx != store.fitems.count - 1 { Hairline() }
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 6)
        }
        .background(Theme.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rXL, style: .continuous))
        .hairline(Theme.borderDefault, radius: Theme.rXL)
        .cardShadow()
    }

    private func sBox(_ v: String, _ l: String, _ bg: Color, _ fg: Color) -> some View {
        VStack(spacing: 5) {
            Text(v).font(Theme.display(32, .semibold)).foregroundColor(fg)
            Text(l).font(Theme.ui(12, .medium)).foregroundColor(fg)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 13)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
    }
}
