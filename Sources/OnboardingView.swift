import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var store: AppStore

    private let labels = ["第 1 步 · 认识秘书", "第 2 步 · 授权", "第 3 步 · 开启智能纪要", "完成"]

    var body: some View {
        ZStack {
            Color(hex: "141413").opacity(0.55).ignoresSafeArea()
                .onTapGesture { }   // swallow taps on the dim layer

            VStack(spacing: 0) {
                progressBars
                VStack(alignment: .leading, spacing: 0) {
                    Text(labels[store.obStep])
                        .font(Theme.mono(11)).tracking(1.0).textCase(.uppercase)
                        .foregroundColor(Theme.inkTertiary)
                        .padding(.bottom, 16)

                    stepContent
                        .frame(maxWidth: .infinity, minHeight: 232, alignment: .topLeading)

                    footer.padding(.top, 24)
                }
                .padding(.horizontal, 36).padding(.top, 12).padding(.bottom, 28)
            }
            .frame(width: 540)
            .background(Theme.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.r2XL, style: .continuous))
            .popShadow()
        }
    }

    private var progressBars: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(i <= store.obStep ? Theme.accent : Color.black.opacity(0.1))
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 24).padding(.top, 18)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch store.obStep {
        case 0: step0
        case 1: step1
        case 2: step2
        default: step3
        }
    }

    private var step0: some View {
        VStack(alignment: .leading, spacing: 0) {
            iconBadge(bg: Theme.accent, fg: .white, symbol: "checkmark", size: 52, radius: 14)
                .padding(.bottom, 20)
            (Text("你好，我是").foregroundColor(Theme.inkPrimary)
                + Text("会后秘书").foregroundColor(Theme.accent)
                + Text("。").foregroundColor(Theme.inkPrimary))
                .font(Theme.display(28, .medium)).tracking(-0.5).padding(.bottom, 12)
            Text("会议一结束，我就把逐字稿整理成「决策 + 待办 + 责任人」，待办直接落成飞书任务，下次开会前还会主动追问完成情况。\n\n妙记负责记录，我负责闭环。整个过程你不用动手。")
                .font(Theme.ui(14.5)).foregroundColor(Theme.inkSecondary).lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var step1: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("需要你授权 7 项权限")
                .font(Theme.display(26, .medium)).tracking(-0.5).foregroundColor(Theme.inkPrimary).padding(.bottom, 8)
            Text("一次性授权，之后全自动。我只读你参加过的会。")
                .font(Theme.ui(14)).foregroundColor(Theme.inkSecondary).padding(.bottom, 18)
            VStack(spacing: 1) {
                permRow("读取会议与妙记纪要")
                permRow("读取逐字稿")
                permRow("创建 / 更新飞书任务")
                permRow("发送私聊消息与卡片")
                permRow("… 及通讯录、群、多维表格 3 项", muted: true)
            }
            .background(Color.black.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
            .hairline(Theme.borderWhisper, radius: Theme.rMD)
        }
    }

    private func permRow(_ text: String, muted: Bool = false) -> some View {
        HStack(spacing: 10) {
            if muted {
                Text("").frame(width: 12)
            } else {
                Text("✓").font(Theme.ui(13, .bold)).foregroundColor(Theme.accent).frame(width: 12)
            }
            Text(text).font(Theme.ui(13)).foregroundColor(muted ? Theme.inkTertiary : Theme.inkPrimary.opacity(0.82))
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.white)
    }

    private var step2: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("关键一步")
                .font(Theme.ui(11.5, .semibold)).foregroundColor(Theme.warn500)
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(Theme.warn50).clipShape(Capsule()).padding(.bottom, 16)
            Text("把「智能纪要」设为默认开启")
                .font(Theme.display(26, .medium)).tracking(-0.5).foregroundColor(Theme.inkPrimary).padding(.bottom, 12)
            (Text("没有逐字稿，秘书就是聋的 —— 这是我能不能帮上忙的生死线。\n在飞书「视频会议设置」里，把")
                .foregroundColor(Theme.inkSecondary)
                + Text("智能纪要默认开启").foregroundColor(Theme.inkPrimary.opacity(0.85)).fontWeight(.semibold)
                + Text("打开，以后每场会我都能拿到原料。").foregroundColor(Theme.inkSecondary))
                .font(Theme.ui(14)).lineSpacing(6).fixedSize(horizontal: false, vertical: true).padding(.bottom, 16)
            (Text("设置 → 视频会议 → 录制与纪要 → ").foregroundColor(Theme.inkSecondary)
                + Text("智能纪要 · 默认开启").foregroundColor(Theme.accentInk).fontWeight(.semibold))
                .font(Theme.ui(13)).lineSpacing(4)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.warmWhite)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
        }
    }

    private var step3: some View {
        VStack(alignment: .leading, spacing: 0) {
            iconBadge(bg: Theme.green50, fg: Theme.green500, symbol: "checkmark", size: 52, radius: 26)
                .padding(.bottom, 20)
            Text("都设好了。")
                .font(Theme.display(28, .medium)).tracking(-0.5).foregroundColor(Theme.inkPrimary).padding(.bottom, 12)
            Text("等你下一个会结束，我会主动来找你 —— 5 分钟内，纪要卡片会出现在你的私聊里。\n\n在那之前，你什么都不用做。")
                .font(Theme.ui(14.5)).foregroundColor(Theme.inkSecondary).lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func iconBadge(bg: Color, fg: Color, symbol: String, size: CGFloat, radius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(bg).frame(width: size, height: size)
            Image(systemName: symbol).font(.system(size: size * 0.52, weight: .semibold)).foregroundColor(fg)
        }
    }

    private var footer: some View {
        HStack {
            if store.obStep < 3 {
                Button { store.obSkip() } label: {
                    Text("稍后").font(Theme.ui(13, .medium)).foregroundColor(Theme.inkTertiary)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                }.buttonStyle(.plain)
            }
            Spacer()
            Button { store.obNext() } label: {
                Text(nextLabel).font(Theme.ui(13, .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    private var nextLabel: String {
        switch store.obStep {
        case 0: return "开始"
        case 3: return "进入秘书"
        default: return "下一步"
        }
    }
}
