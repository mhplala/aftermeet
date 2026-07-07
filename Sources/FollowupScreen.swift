import SwiftUI

struct FollowupScreen: View {
    @EnvironmentObject var store: AppStore
    @State private var showForward = false

    /// 真数据模式：同名会议重复出现 → 上一场待办的对比卡；否则样例。
    private var real: AppStore.RecurringCard? { store.recurringCard }
    private var items: [FollowItem] { real?.items ?? store.fitems }

    private var doneN: Int { items.filter { $0.done }.count }
    private var notDoneN: Int { items.filter { !$0.done }.count }
    private var rate: Int { items.isEmpty ? 0 : Int((Double(doneN) / Double(items.count) * 100).rounded()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Overline("会前 · 自动追问", tracking: 1.2).padding(.bottom, 8)
                Text("进度追问卡")
                    .font(Theme.display(36, .medium)).tracking(-0.7).foregroundColor(Theme.inkPrimary)
                Text(subtitle)
                    .font(Theme.display(15, .regular)).italic()
                    .foregroundColor(Theme.inkSecondary)
                    .padding(.top, 8).padding(.bottom, 24)
                    .fixedSize(horizontal: false, vertical: true)

                if store.usingRealData && real == nil {
                    Card(padding: 0) {
                        EmptyState(icon: "clock.arrow.circlepath",
                                   title: "还没识别到周期性会议",
                                   message: "会前追问靠「同一主题的会议再次发生」触发。\n等某场会重复出现，我把上次待办的完成情况整理到这里。")
                    }
                } else {
                    card
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
    }

    private var subtitle: String {
        if let real {
            return "「\(real.title)」开过不止一次。上一场的待办进度我盘好了，公开点名前你先过一眼。"
        }
        return store.usingRealData
            ? "会前 2 小时，我会盘点上一场同主题会议的待办完成情况，放在这里等你过目。"
            : "下周二 10:00「产品周例会」开始前，我整理了上次的待办进度。公开点名前，你先过一眼。"
    }

    private var card: some View {
        VStack(spacing: 0) {
            cardHeader
            Hairline()
            statRow
            Hairline()
            itemRows
            footer
        }
        .background(Theme.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rXL, style: .continuous))
        .hairline(Theme.borderDefault, radius: Theme.rXL)
        .cardShadow()
    }

    private var cardHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous)
                    .fill(Theme.ink1000).frame(width: 40, height: 40)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 19, weight: .regular)).foregroundColor(Theme.brand300)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("上次「\(real?.title ?? "产品周例会")」的待办进度")
                    .font(Theme.display(17, .medium)).foregroundColor(Theme.inkPrimary)
                Text(real.map { "\($0.prevMeta)" } ?? "6月3日 周二 · 6 条待办")
                    .font(Theme.mono(11)).foregroundColor(Theme.inkTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
    }

    private var statRow: some View {
        HStack(spacing: 14) {
            statBox(value: "\(doneN)", label: "已完成", bg: Theme.green50, fg: Theme.green700)
            statBox(value: "\(notDoneN)", label: "未动", bg: Theme.danger50, fg: Theme.danger500)
            statBox(value: "\(rate)", unit: "%", label: "闭环率", bg: Theme.warmWhite, fg: Theme.inkPrimary, labelFg: Theme.inkSecondary)
        }
        .padding(.horizontal, 24).padding(.vertical, 22)
    }

    private func statBox(value: String, unit: String? = nil, label: String,
                         bg: Color, fg: Color, labelFg: Color? = nil) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value).font(Theme.display(40, .medium)).foregroundColor(fg)
                if let unit { Text(unit).font(Theme.display(20, .medium)).foregroundColor(fg) }
            }
            Text(label).font(Theme.ui(12.5, .medium)).foregroundColor(labelFg ?? fg)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
    }

    private var itemRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, f in
                Button {
                    if let real {
                        store.toggleFollowItem(text: f.text, meetingTitle: real.title)
                    } else {
                        store.toggleFitem(f.id)
                    }
                } label: {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            mark(done: f.done)
                            Text(f.text)
                                .font(Theme.ui(13.5))
                                .foregroundColor(f.done ? Theme.inkTertiary : Theme.inkPrimary.opacity(0.85))
                            Spacer()
                            Text(f.owner).font(Theme.ui(12)).foregroundColor(Theme.inkSecondary)
                            Text(f.done ? "已完成" : "未动")
                                .font(Theme.ui(11, .semibold))
                                .foregroundColor(f.done ? Theme.green700 : Theme.danger500)
                                .frame(width: 62)
                                .padding(.vertical, 3)
                                .background(f.done ? Theme.green50 : Theme.danger50)
                                .clipShape(Capsule())
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        if idx != items.count - 1 { Hairline() }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 16)
    }

    private func mark(done: Bool) -> some View {
        ZStack {
            Circle().fill(done ? Theme.green500 : Color.clear).frame(width: 18, height: 18)
                .overlay { if !done { Circle().strokeBorder(Theme.danger500.opacity(0.55), lineWidth: 1.5) } }
            if done {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundColor(.white)
            } else {
                Circle().fill(Theme.danger500).frame(width: 6, height: 6)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("公开转发会 @ 未完成项的负责人。要不要点名，你说了算。")
                .font(Theme.ui(12.5)).foregroundColor(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button { store.showToast("已存为草稿，仅你可见") } label: {
                Text("仅自己看").font(Theme.ui(13, .semibold)).foregroundColor(Theme.inkPrimary.opacity(0.85))
                    .padding(.horizontal, 15).padding(.vertical, 9)
                    .background(Theme.white)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
                    .hairline(Theme.borderDefault, radius: Theme.rMD)
            }.buttonStyle(.plain).fixedSize()
            Button {
                if real != nil {
                    showForward = true
                } else {
                    store.showToast("进度追问卡已发到「产品周例会」群（演示）")
                }
            } label: {
                Text("发到会议群").font(Theme.ui(13, .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
            }
            .buttonStyle(.plain).fixedSize()
            .popover(isPresented: $showForward, arrowEdge: .top) {
                if let real {
                    ForwardPicker(meetingTitle: real.title,
                                  copyMarkdown: AppStore.followupMarkdown(real)) { chat in
                        showForward = false
                        store.send(markdown: AppStore.followupMarkdown(real), to: chat, what: "进度追问卡")
                    }
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
        .background(Theme.warmWhite)
    }
}
