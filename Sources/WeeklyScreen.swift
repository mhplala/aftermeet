import SwiftUI

struct WeeklyScreen: View {
    @EnvironmentObject var store: AppStore

    private let procrastinators: [Procrastinator] = [
        .init(rank: "1", text: "灰度首周用户访谈提纲", owner: "苏萌", days: "12"),
        .init(rank: "2", text: "纪要卡片折叠态前端联调", owner: "周岚", days: "9"),
        .init(rank: "3", text: "权限 scope 文档补全", owner: "高翔", days: "8"),
        .init(rank: "4", text: "欢迎卡 A/B 文案", owner: "陈默", days: "6"),
        .init(rank: "5", text: "周报台账字段对齐", owner: "王凯", days: "5"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.bottom, 24)
                statRow.padding(.bottom, 16)
                if store.usingRealData {
                    Card(padding: 0) {
                        EmptyState(icon: "chart.line.uptrend.xyaxis",
                                   title: "趋势还在攒数据",
                                   message: "闭环率走势和拖延 Top 5 需要跨周的历史。\n等同步过几周会议、待办开始闭环后，这里自动出图。")
                    }
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        chartCard
                        topCard.frame(width: 360)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Overline("6月9日 – 6月13日 · 周五傍晚", tracking: 1.2).padding(.bottom, 8)
                (Text("本周").foregroundColor(Theme.inkPrimary)
                    + Text("会议回顾").foregroundColor(Theme.accent).italic())
                    .font(Theme.display(38, .medium)).tracking(-0.9)
            }
            Spacer()
            Button { store.showToast("会议台账已生成，多维表格链接已复制") } label: {
                Text("生成会议台账 →").font(Theme.ui(13, .semibold)).foregroundColor(Theme.inkPrimary.opacity(0.85))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Theme.white)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
                    .hairline(Theme.borderDefault, radius: Theme.rMD)
            }.buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var statRow: some View {
        if store.usingRealData {
            HStack(spacing: 14) {
                StatCard(label: "已同步会议", value: "\(store.meetings.count)", sub: "本期", valueSize: 34)
                StatCard(label: "产生待办", value: "\(store.ctodos.count)", sub: "\(store.crossDone) 已完成", valueSize: 34)
                StatCard(label: "闭环率", value: "\(store.closeRatePct)", unit: "%", sub: "实时",
                         subColor: Theme.green500, valueColor: Theme.accent, valueSize: 34)
                StatCard(label: "长期未完成", value: "0", sub: "攒数据中", valueSize: 34)
            }
        } else {
            HStack(spacing: 14) {
                StatCard(label: "会议", value: "11", sub: "较上周 +2", valueSize: 34)
                StatCard(label: "产生待办", value: "38", sub: "28 已确认", valueSize: 34)
                StatCard(label: "闭环率", value: "43", unit: "%", sub: "▲ +7%",
                         subColor: Theme.green500, valueColor: Theme.accent, valueSize: 34)
                StatCard(label: "长期未完成", value: "5", sub: "需要催一催",
                         valueColor: Theme.danger500, valueSize: 34)
            }
        }
    }

    private var chartCard: some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 0) {
                Text("闭环率走势").font(Theme.display(18, .medium)).foregroundColor(Theme.inkPrimary)
                Text("过去 6 周，待办按期完成的比例。")
                    .font(Theme.display(13, .regular)).italic()
                    .foregroundColor(Theme.inkTertiary).padding(.top, 2).padding(.bottom, 20)
                CloseRateChart()
            }
        }
    }

    private var topCard: some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 0) {
                Text("拖延 Top 5").font(Theme.display(18, .medium)).foregroundColor(Theme.inkPrimary)
                Text("最久未更新的待办。")
                    .font(Theme.display(13, .regular)).italic()
                    .foregroundColor(Theme.inkTertiary).padding(.top, 2).padding(.bottom, 16)
                ForEach(Array(procrastinators.enumerated()), id: \.element.id) { idx, p in
                    VStack(spacing: 0) {
                        HStack(spacing: 11) {
                            Text(p.rank).font(Theme.mono(12, .semibold)).foregroundColor(Theme.inkMuted).frame(width: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.text).font(Theme.ui(13)).foregroundColor(Theme.inkPrimary.opacity(0.85)).lineLimit(1)
                                Text(p.owner).font(Theme.mono(10.5)).foregroundColor(Theme.inkTertiary)
                            }
                            Spacer(minLength: 6)
                            Text("\(p.days)天").font(Theme.mono(11, .semibold)).foregroundColor(Theme.danger500)
                        }
                        .padding(.vertical, 10)
                        if idx != procrastinators.count - 1 { Hairline() }
                    }
                }
            }
        }
    }
}

// MARK: - Close-rate line chart

struct CloseRateChart: View {
    private let values: [Double] = [16, 18, 26, 31, 38, 43]
    private let maxV: Double = 60
    private let labels = ["第1周", "第2周", "第3周", "第4周", "第5周", "本周"]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: 0) {
                axisLabel("60"); Spacer(); axisLabel("40"); Spacer(); axisLabel("20"); Spacer(); axisLabel("0")
            }
            .frame(width: 20, height: 150)

            VStack(spacing: 6) {
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    let pts = points(w: w, h: h)
                    ZStack {
                        Path { p in
                            for f in [0.333, 0.666] {
                                p.move(to: CGPoint(x: 0, y: h * f))
                                p.addLine(to: CGPoint(x: w, y: h * f))
                            }
                        }.stroke(Color.black.opacity(0.06), lineWidth: 1)

                        Path { p in
                            p.move(to: CGPoint(x: 0, y: h))
                            for pt in pts { p.addLine(to: pt) }
                            p.addLine(to: CGPoint(x: w, y: h))
                            p.closeSubpath()
                        }.fill(LinearGradient(
                            colors: [Theme.green500.opacity(0.16), Theme.green500.opacity(0)],
                            startPoint: .top, endPoint: .bottom))

                        Path { p in
                            p.move(to: pts[0])
                            for pt in pts.dropFirst() { p.addLine(to: pt) }
                        }.stroke(Theme.green500, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                        if let end = pts.last {
                            Circle().fill(Theme.green500).frame(width: 8, height: 8).position(end)
                        }
                    }
                }
                .frame(height: 150)

                HStack(spacing: 0) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { idx, l in
                        axisLabel(l)
                        if idx != labels.count - 1 { Spacer() }
                    }
                }
            }
        }
    }

    private func points(w: CGFloat, h: CGFloat) -> [CGPoint] {
        values.enumerated().map { i, v in
            CGPoint(x: w * CGFloat(i) / CGFloat(values.count - 1),
                    y: h - h * CGFloat(v / maxV))
        }
    }

    private func axisLabel(_ s: String) -> some View {
        Text(s).font(Theme.mono(10)).foregroundColor(Theme.inkTertiary)
    }
}
