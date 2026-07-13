import SwiftUI
import AppKit
import AVFoundation
import CoreGraphics

/// 首启引导：围绕真实的就绪条件展开 —— 每一步都是可完成的动作 + 实时状态，
/// 不描述不存在的权限，不承诺未就绪的能力。
struct OnboardingView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var downloader = ModelDownloader()

    @State private var screenGranted = CGPreflightScreenCaptureAccess()
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    private let labels = ["欢迎", "转写模型", "系统权限", "飞书接入", "就绪"]
    private let recommendedModel = "ggml-medium-q5_0.bin"

    private var modelReady: Bool {
        FileManager.default.fileExists(atPath: Whisper.model) || localModelExists
    }
    private var localModelExists: Bool {
        FileManager.default.fileExists(
            atPath: ModelDownloader.dir.appendingPathComponent(recommendedModel).path)
    }

    var body: some View {
        ZStack {
            Theme.dimOverlay.ignoresSafeArea()
                .onTapGesture { }   // swallow taps on the dim layer

            VStack(spacing: 0) {
                progressBars
                VStack(alignment: .leading, spacing: 0) {
                    Text("第 \(store.obStep + 1) 步 · \(labels[min(store.obStep, labels.count - 1)])")
                        .font(Theme.mono(11)).tracking(1.0).textCase(.uppercase)
                        .foregroundColor(Theme.inkTertiary)
                        .padding(.bottom, 16)

                    stepContent
                        .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)

                    footer.padding(.top, 22)
                }
                .padding(.horizontal, 36).padding(.top, 12).padding(.bottom, 26)
            }
            .frame(width: 560)
            .background(Theme.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.r2XL, style: .continuous))
            .popShadow()
        }
    }

    private var progressBars: some View {
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(i <= store.obStep ? Theme.blue500 : Theme.paper300)
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 24).padding(.top, 18)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch store.obStep {
        case 0: welcome
        case 1: modelStep
        case 2: permissionStep
        case 3: larkStep
        default: readyStep
        }
    }

    // MARK: 1 · 欢迎

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "5b93f8"), Color(hex: "2e6ae0")],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 52, height: 52)
                Image(systemName: "waveform")
                    .font(.system(size: 24, weight: .semibold)).foregroundColor(.white)
            }
            .padding(.bottom, 18)
            Text("开完会，事情自动往前走")
                .font(Theme.display(27, .semibold)).tracking(-0.5)
                .foregroundColor(Theme.inkPrimary).padding(.bottom, 12)
            Text("会中音频在本机实时转写（不上传），结束后自动生成结构化纪要：决策、待办、分歧、时间线。待办可一键创建为飞书任务，下次开会前自动汇总完成进度。\n\n接下来两步完成必要配置，大约一分钟。")
                .font(Theme.ui(14)).foregroundColor(Theme.inkSecondary).lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 2 · 转写模型（必需，就地下载）

    private var modelStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("下载转写模型")
                .font(Theme.display(24, .semibold)).tracking(-0.4)
                .foregroundColor(Theme.inkPrimary).padding(.bottom, 8)
            Text("转写引擎已内置。模型（514 MB）下载一次，之后完全离线运行。")
                .font(Theme.ui(13.5)).foregroundColor(Theme.inkSecondary).padding(.bottom, 18)

            HStack(spacing: 12) {
                statusIcon(ok: modelReady, active: downloader.progress[recommendedModel] != nil)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Whisper Medium Q5 · 中文推荐")
                        .font(Theme.ui(13.5, .medium)).foregroundColor(Theme.inkPrimary)
                    if let err = downloader.errors[recommendedModel] {
                        Text(err).font(Theme.mono(10)).foregroundColor(Theme.danger500)
                    } else if modelReady {
                        Text("已就绪").font(Theme.mono(10)).foregroundColor(Theme.green700)
                    } else {
                        Text("ggml-medium-q5_0.bin · 514 MB").font(Theme.mono(10)).foregroundColor(Theme.inkMuted)
                    }
                }
                Spacer()
                if let p = downloader.progress[recommendedModel] {
                    ProgressView(value: p).frame(width: 110)
                    Text("\(Int(p * 100))%").font(Theme.mono(11)).foregroundColor(Theme.inkTertiary)
                        .frame(width: 36, alignment: .trailing)
                } else if !modelReady {
                    Button { downloader.download(recommendedModel) } label: {
                        Text("下载").font(Theme.ui(12.5, .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(Theme.inkGrad).clipShape(Capsule())
                            .contentShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Theme.warmWhite)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rLG - 2, style: .continuous))

            if !modelReady && downloader.errors[recommendedModel] != nil {
                // 内网/代理环境 app 内直连经常不通，浏览器（走用户自己的代理）是兜底路
                HStack(spacing: 10) {
                    Button {
                        if let url = URL(string: ModelDownloader.sources[0] + recommendedModel) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("用浏览器下载").font(Theme.ui(12, .semibold)).foregroundColor(Theme.inkSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Theme.white).clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(Theme.borderDefault, lineWidth: 1))
                            .contentShape(Capsule())
                    }.buttonStyle(.plain)
                    Button {
                        if case .imported = ModelDownloader.importModelInteractively() {
                            downloader.errors[recommendedModel] = nil   // 触发重渲染，绿勾亮起
                        }
                    } label: {
                        Text("导入下载好的文件…").font(Theme.ui(12, .semibold)).foregroundColor(Theme.inkSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Theme.white).clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(Theme.borderDefault, lineWidth: 1))
                            .contentShape(Capsule())
                    }.buttonStyle(.plain)
                    Spacer()
                }
                .padding(.top, 12)
            } else if !modelReady && downloader.progress[recommendedModel] == nil {
                Text("也可以先跳过，稍后在 设置 → 转写模型 下载；下载完成前无法录制。")
                    .font(Theme.mono(10.5)).foregroundColor(Theme.inkMuted)
                    .padding(.top, 12)
            }
        }
    }

    // MARK: 3 · 系统权限（预检 + 一键请求）

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("两项系统权限")
                .font(Theme.display(24, .semibold)).tracking(-0.4)
                .foregroundColor(Theme.inkPrimary).padding(.bottom, 8)
            Text("屏幕录制用于采集系统音频（对方的声音），麦克风用于收录你的发言。音频只在本机处理。")
                .font(Theme.ui(13.5)).foregroundColor(Theme.inkSecondary).padding(.bottom, 18)

            VStack(spacing: 1) {
                permissionRow(icon: "rectangle.inset.filled.badge.record", name: "屏幕录制",
                              granted: screenGranted) {
                    if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
                    screenGranted = CGPreflightScreenCaptureAccess()
                }
                permissionRow(icon: "mic", name: "麦克风", granted: micGranted) {
                    AVCaptureDevice.requestAccess(for: .audio) { ok in
                        DispatchQueue.main.async { micGranted = ok }
                    }
                }
            }
            .background(Theme.warmWhite)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rLG - 2, style: .continuous))

            Text("如果没有弹出授权窗口，请在 系统设置 → 隐私与安全性 中手动勾选 Aftermeet。")
                .font(Theme.mono(10.5)).foregroundColor(Theme.inkMuted)
                .padding(.top, 12)
        }
        .onAppear(perform: refreshGrants)
        // 用户去系统设置勾完切回来，状态要跟着变
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in refreshGrants() }
    }

    private func refreshGrants() {
        screenGranted = CGPreflightScreenCaptureAccess()
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func permissionRow(icon: String, name: String, granted: Bool,
                               request: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(Theme.inkSecondary)
                .frame(width: 20)
            Text(name).font(Theme.ui(13.5)).foregroundColor(Theme.inkPrimary)
            Spacer()
            if granted {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13))
                    Text("已授权").font(Theme.ui(12, .medium))
                }.foregroundColor(Theme.green700)
            } else {
                Button(action: request) {
                    Text("授权").font(Theme.ui(12, .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Theme.inkGrad).clipShape(Capsule())
                        .contentShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.white)
    }

    // MARK: 4 · 飞书（可选）

    private var larkStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("飞书接入")
                    .font(Theme.display(24, .semibold)).tracking(-0.4)
                    .foregroundColor(Theme.inkPrimary)
                Pill(text: "可选", bg: Theme.warmWhite2, fg: Theme.inkTertiary, size: 11)
            }
            .padding(.bottom, 8)
            Text("装好 lark-cli 并登录后自动接入：待办一键建飞书任务、日历交叉比对自动命名、妙记纪要同步。不装也不影响本地转写与纪要。")
                .font(Theme.ui(13.5)).foregroundColor(Theme.inkSecondary).padding(.bottom, 18)

            HStack(spacing: 12) {
                statusIcon(ok: Lark.available, active: false, missingIcon: "circle.dashed")
                VStack(alignment: .leading, spacing: 2) {
                    Text(Lark.available ? "lark-cli 已检测到，飞书功能已启用" : "未检测到 lark-cli")
                        .font(Theme.ui(13.5, .medium)).foregroundColor(Theme.inkPrimary)
                    Text(Lark.available ? Lark.cli : "安装并登录后重启应用即自动接入")
                        .font(Theme.mono(10)).foregroundColor(Theme.inkMuted)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
            }
            .padding(14)
            .background(Theme.warmWhite)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rLG - 2, style: .continuous))

            if Lark.available {
                (Text("建议：在飞书 设置 → 视频会议 → 录制与纪要 中开启 ")
                    .foregroundColor(Theme.inkSecondary)
                    + Text("智能纪要默认开启").foregroundColor(Theme.inkPrimary).fontWeight(.semibold)
                    + Text("，线上会议的妙记纪要才能自动同步进来。").foregroundColor(Theme.inkSecondary))
                    .font(Theme.ui(12.5)).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
        }
    }

    // MARK: 5 · 就绪清单

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(allReady ? "一切就绪" : "基本就绪")
                .font(Theme.display(24, .semibold)).tracking(-0.4)
                .foregroundColor(Theme.inkPrimary).padding(.bottom, 14)

            VStack(spacing: 1) {
                checkRow("转写引擎", ok: Whisper.serverAvailable, hint: "内置")
                checkRow("转写模型", ok: modelReady, hint: modelReady ? "已就绪" : "设置 → 转写模型 下载")
                checkRow("屏幕录制权限", ok: screenGranted, hint: screenGranted ? "已授权" : "首次录制时会再次请求")
                checkRow("麦克风权限", ok: micGranted, hint: micGranted ? "已授权" : "首次录制时会再次请求")
                checkRow("飞书", ok: Lark.available, hint: Lark.available ? "已接入" : "可选，未接入")
            }
            .background(Theme.warmWhite)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rLG - 2, style: .continuous))

            Text(allReady
                 ? "检测到会议时，顶栏录制条会提示开始记录；结束后纪要自动生成。"
                 : "缺失项随时可以在设置中补齐；补齐前录制不可用。")
                .font(Theme.ui(12.5)).foregroundColor(Theme.inkSecondary)
                .padding(.top, 14)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear(perform: refreshGrants)
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in refreshGrants() }
    }

    private var allReady: Bool { Whisper.serverAvailable && modelReady && screenGranted && micGranted }

    private func checkRow(_ name: String, ok: Bool, hint: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 14))
                .foregroundColor(ok ? Theme.green500 : Theme.inkMuted)
                .frame(width: 20)
            Text(name).font(Theme.ui(13.5)).foregroundColor(Theme.inkPrimary)
            Spacer()
            Text(hint).font(Theme.mono(10.5)).foregroundColor(ok ? Theme.inkTertiary : Theme.warn500)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.white)
    }

    // MARK: 底座

    private func statusIcon(ok: Bool, active: Bool, missingIcon: String = "arrow.down.circle") -> some View {
        Group {
            if active {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: ok ? "checkmark.circle.fill" : missingIcon)
                    .font(.system(size: 20))
                    .foregroundColor(ok ? Theme.green500 : Theme.inkMuted)
            }
        }
        .frame(width: 24)
    }

    private var footer: some View {
        HStack {
            if store.obStep < 4 {
                Button { store.obSkip() } label: {
                    Text("稍后设置").font(Theme.ui(13, .medium)).foregroundColor(Theme.inkTertiary)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Spacer()
            Button { store.obNext() } label: {
                Text(nextLabel).font(Theme.ui(13, .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .background(Theme.inkGrad)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            }.buttonStyle(.plain)
        }
    }

    private var nextLabel: String {
        switch store.obStep {
        case 0: return "开始配置"
        case 4: return "开始使用"
        default: return "下一步"
        }
    }
}
