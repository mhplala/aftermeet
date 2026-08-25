import SwiftUI

/// 顶栏常驻的录制状态条 —— 「会中转写」从一级目录降级成随处可见的状态。
/// 空闲：● 录制　检测到会议：绿色高亮　录制中：红色计时　提炼中：整理中　完成：✓ 点击查看
struct RecStrip: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var cap: CaptureService

    private enum Phase { case idle, detected, recording, refining, done }
    private var phase: Phase {
        if store.refining { return .refining }
        if cap.isCapturing { return .recording }        // 新录制进行中：完成态让位
        if store.freshLiveID != nil { return .done }
        if store.meetingActive { return .detected }
        return .idle
    }

    private var timeString: String {
        String(format: "%02d:%02d", cap.elapsed / 60, cap.elapsed % 60)
    }

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 8) {
                dot
                label
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(background)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
            .shadow(color: glowColor, radius: 7, x: 0, y: 3)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $store.showRecPanel, arrowEdge: .bottom) {
            RecPanel()
                .environmentObject(store)
                .environmentObject(cap)
        }
        .animation(.easeOut(duration: 0.18), value: cap.isCapturing)
        .animation(.easeOut(duration: 0.18), value: store.meetingActive)
    }

    private func tap() {
        switch phase {
        case .done: store.openFreshLive()
        default:    store.showRecPanel.toggle()
        }
    }

    @ViewBuilder private var dot: some View {
        switch phase {
        case .idle:
            Circle().fill(Theme.inkMuted).frame(width: 8, height: 8)
        case .detected:
            PulsingDot(color: Theme.blue500)
        case .recording:
            if cap.isPaused {
                Circle().fill(Theme.warn500).frame(width: 8, height: 8)
            } else {
                PulsingDot(color: Theme.danger500)
            }
        case .refining:
            ProgressView().controlSize(.mini)
        case .done:
            Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundColor(.white)
        }
    }

    @ViewBuilder private var label: some View {
        switch phase {
        // 只表状态、不重复“录制”动作——动作在右边的 RecControls 里，两者不能都叫“录制”
        case .idle:
            Text("空闲").font(Theme.ui(12.5, .semibold)).foregroundColor(Theme.inkSecondary)
        case .detected:
            Text("检测到会议").font(Theme.ui(12.5, .semibold)).foregroundColor(Theme.blue700)
        case .recording:
            HStack(spacing: 7) {
                Text(cap.isPaused ? "已暂停" : "录制中").font(Theme.ui(12.5, .semibold))
                Text(timeString).font(Theme.mono(12, .medium))
            }.foregroundColor(cap.isPaused ? Theme.warn500 : Theme.danger500)
        case .refining:
            Text("整理中…").font(Theme.ui(12.5, .semibold)).foregroundColor(Theme.inkSecondary)
        case .done:
            Text("纪要已生成 · 点击查看").font(Theme.ui(12.5, .semibold)).foregroundColor(.white)
        }
    }

    private var background: AnyShapeStyle {
        switch phase {
        case .idle, .refining: return AnyShapeStyle(Theme.glassFill)
        case .detected:        return AnyShapeStyle(Theme.blue50)
        case .recording:       return AnyShapeStyle(cap.isPaused ? Theme.warn50 : Theme.danger50)
        case .done:            return AnyShapeStyle(Theme.inkGrad)
        }
    }

    private var borderColor: Color {
        switch phase {
        case .idle, .refining: return Theme.borderDefault
        case .detected:        return Theme.blue500.opacity(0.4)
        case .recording:       return (cap.isPaused ? Theme.warn500 : Theme.danger500).opacity(0.4)
        case .done:            return .clear
        }
    }

    private var glowColor: Color {
        switch phase {
        case .idle, .refining: return Color.black.opacity(0.14)
        case .detected:        return Theme.blue500.opacity(0.22)
        case .recording:       return (cap.isPaused ? Theme.warn500 : Theme.danger500).opacity(0.30)
        case .done:            return Color.black.opacity(0.30)
        }
    }
}

/// 顶栏常驻操作区：录制 / 暂停 / 字幕窗。
/// 之前这些只藏在状态药丸的弹层里，开会时每次都要先点开弹层——高频操作不该多一跳。
struct RecControls: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var cap: CaptureService
    @ObservedObject private var captionCtl = LiveCaptionWindowController.shared

    var body: some View {
        HStack(spacing: 6) {
            if cap.isCapturing {
                pill(cap.isPaused ? "play.fill" : "pause.fill",
                     cap.isPaused ? "继续" : "暂停",
                     tint: cap.isPaused ? Theme.accent : Theme.inkSecondary) {
                    store.togglePause()
                }
                pill("stop.fill", "停止", tint: Theme.danger500) { store.toggleCapture() }
            } else {
                pill("record.circle", "录制", tint: Theme.inkSecondary) { store.toggleCapture() }
            }
            pill("captions.bubble", captionCtl.isOpen ? "字幕开" : "字幕",
                 tint: captionCtl.isOpen ? Theme.blue700 : Theme.inkSecondary) {
                LiveCaptionWindowController.shared.toggle(capture: cap)
            }
        }
    }

    private func pill(_ icon: String, _ label: String, tint: Color,
                      _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10.5, weight: .semibold))
                Text(label).font(Theme.ui(11.5, .semibold))
            }
            .foregroundColor(tint)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.glassFill)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.borderDefault, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct PulsingDot: View {
    let color: Color
    @State private var on = false
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .glow(color, radius: 6, opacity: 0.8)
            .opacity(on ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

// MARK: - 展开面板（原会中转写页的浓缩版）

struct RecPanel: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var cap: CaptureService
    @ObservedObject private var captionCtl = LiveCaptionWindowController.shared
    @State private var nameEdit = ""

    private var engineReady: Bool { CloudASRConfig.isConfigured || Whisper.available() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("会中 · 实时转写")
                    .font(Theme.mono(10, .semibold)).tracking(1.0)
                    .foregroundColor(Theme.inkMuted).textCase(.uppercase)
                if cap.isCapturing { engineTag }
                Spacer()
                Button {
                    LiveCaptionWindowController.shared.toggle(capture: cap)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "captions.bubble").font(.system(size: 10))
                        Text(captionCtl.isOpen ? "关闭字幕窗" : "字幕窗")
                            .font(Theme.ui(11, .semibold))
                    }
                    .foregroundColor(Theme.inkSecondary)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Theme.white).clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Theme.borderDefault, lineWidth: 1))
                    .contentShape(Capsule())
                }.buttonStyle(.plain)
            }

            if !engineReady { missingEngineRow }
            nameRow
            if !cap.calendarSuggestion.isEmpty && nameEdit.isEmpty { suggestionRow }
            autoStartRow

            if cap.isCapturing || !cap.liveLines.isEmpty { liveBox }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cap.isCapturing ? "录制中 \(timeString)" : (store.refining ? "整理中…" : "未开始"))
                        .font(Theme.ui(13, .semibold)).foregroundColor(Theme.inkPrimary)
                    Text(cap.isCapturing
                         ? (cap.usingCloud ? "音频经云端处理 · 请确保参会者知情" : "音频仅在本机处理 · 请确保参会者知情")
                         : (CloudASRConfig.isConfigured ? "默认走云端转写 · 请确保参会者知情" : "音频仅在本机处理 · 请确保参会者知情"))
                        .font(Theme.mono(9.5)).foregroundColor(Theme.inkTertiary)
                }
                Spacer()
                controlButton
            }
            // 重连中：音频仍在落盘，只是这段暂时没有文字，得让用户看见而不是干等
            if cap.isCapturing, cap.cloudReconnecting {
                Text(cap.status + "（音频仍在录，这段稍后可能缺字）")
                    .font(Theme.ui(11)).foregroundColor(Theme.warn500)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 启动失败的原因（缺权限/引擎中断）原来只写进这个字段但没显示 —— 必须可见
            if !cap.isCapturing, statusIsError {
                Text(cap.status)
                    .font(Theme.ui(11)).foregroundColor(Theme.danger500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear { if nameEdit.isEmpty { nameEdit = cap.meetingName } }
        .onChange(of: cap.meetingName) { _, new in if !new.isEmpty && nameEdit.isEmpty { nameEdit = new } }
    }

    private var timeString: String {
        String(format: "%02d:%02d", cap.elapsed / 60, cap.elapsed % 60)
    }

    private var statusIsError: Bool {
        cap.status.contains("权限") || cap.status.contains("未找到") || cap.status.contains("中断")
    }

    /// 云端未配置、本地引擎又缺失/缺模型：录制无法开始，给出去处
    private var missingEngineRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12)).foregroundColor(Theme.warn500)
            VStack(alignment: .leading, spacing: 1) {
                Text(Whisper.serverAvailable ? "缺少转写模型" : "转写引擎异常")
                    .font(Theme.ui(12, .semibold)).foregroundColor(Theme.inkPrimary)
                Text(Whisper.serverAvailable ? "配置云端转写，或下载本地模型后即可录制" : "配置云端转写，或重新安装应用 / brew install whisper-cpp")
                    .font(Theme.mono(9.5)).foregroundColor(Theme.inkTertiary)
            }
            Spacer()
            Button {
                store.showRecPanel = false
                store.go(.settings)
            } label: {
                Text("去设置").font(Theme.ui(11.5, .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Theme.inkGrad).clipShape(Capsule())
                    .contentShape(Capsule())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(Theme.warn50)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
    }

    /// 录制中才有意义——启动前不知道最终走哪条路（云端可能中途断线重连，甚至退回本地）
    private var engineTag: some View {
        let label = cap.cloudReconnecting ? "重连中" : (cap.usingCloud ? "云端" : "本地")
        let fg = cap.cloudReconnecting ? Theme.warn500 : (cap.usingCloud ? Theme.blue700 : Theme.inkSecondary)
        let bg = cap.cloudReconnecting ? Theme.warn50 : (cap.usingCloud ? Theme.blue50 : Theme.glassFill)
        return Text(label)
            .font(Theme.mono(9, .semibold)).tracking(0.4)
            .foregroundColor(fg)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(bg)
            .clipShape(Capsule())
    }

    private var nameRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil.and.list.clipboard")
                .font(.system(size: 12)).foregroundColor(Theme.inkTertiary)
            TextField("会议名称(留空则根据内容自动生成)", text: $nameEdit)
                .textFieldStyle(.plain).font(Theme.ui(12.5)).foregroundColor(Theme.inkPrimary)
                .onSubmit { cap.setMeetingName(nameEdit) }
            if !nameEdit.isEmpty {
                Button { cap.setMeetingName(nameEdit) } label: {
                    Text("确定").font(Theme.ui(11.5, .semibold)).foregroundColor(Theme.accent)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(Theme.warmWhite)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
        .hairline(Theme.borderWhisper, radius: Theme.rMD)
    }

    private var suggestionRow: some View {
        HStack(spacing: 7) {
            Text("当前日程").font(Theme.mono(10)).foregroundColor(Theme.inkTertiary)
            Button {
                nameEdit = cap.calendarSuggestion
                cap.setMeetingName(cap.calendarSuggestion)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar").font(.system(size: 9.5))
                    Text(cap.calendarSuggestion).font(Theme.ui(11, .medium)).lineLimit(1)
                }
                .foregroundColor(Theme.blue700)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Theme.blue50).clipShape(Capsule())
            }.buttonStyle(.plain)
            Spacer()
        }
    }

    private var autoStartRow: some View {
        HStack(spacing: 9) {
            Toggle("", isOn: Binding(get: { store.autoStart }, set: { store.setAutoStart($0) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            Text("检测到会议自动开始记录").font(Theme.ui(12)).foregroundColor(Theme.inkSecondary)
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(store.meetingActive ? Theme.accent : Theme.inkMuted).frame(width: 6, height: 6)
                Text(store.meetingActive ? "麦克风活跃" : "无会议")
                    .font(Theme.mono(9.5)).foregroundColor(Theme.inkTertiary)
            }
        }
    }

    /// 实时预览：按分句成行，最后一句（服务端还在改写的）用浅色标出，让人一眼看出
    /// "哪些已经定了、哪句还在成形"。只渲染 CaptureService 已经封顶的最近若干条，
    /// 不拿整篇几万字去做布局测量（那会卡死主线程）。
    private var liveBox: some View {
        let lines = cap.liveLines
        let pending = cap.pendingLine
        let isEmpty = lines.isEmpty && pending.isEmpty
        return ScrollViewReader { proxy in
            ScrollView {
                if isEmpty {
                    HStack(spacing: 6) {
                        if cap.isCapturing { PulsingDot(color: Theme.inkMuted) }
                        Text(cap.isCapturing ? "正在聆听…" : "尚无内容")
                            .font(Theme.ui(12.5)).foregroundColor(Theme.inkTertiary)
                        Spacer()
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(Theme.ui(12.5))
                                .foregroundColor(Theme.inkPrimary.opacity(0.88))
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !pending.isEmpty {
                            Text(pending)
                                .font(Theme.ui(12.5))
                                .foregroundColor(Theme.inkTertiary)   // 还会变，视觉上弱化
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Color.clear.frame(height: 1).id("bottom")
            }
            .frame(height: 168)
            // 用廉价的计数/长度变化触发，不拿长串做 diff
            .onChange(of: lines.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: pending.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .padding(10)
        .background(Theme.warmWhite)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
        .hairline(Theme.borderWhisper, radius: Theme.rMD)
    }

    private var controlButton: some View {
        Button {
            store.toggleCapture()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: cap.isCapturing ? "stop.fill" : "record.circle")
                    .font(.system(size: 11, weight: .semibold))
                Text(cap.isCapturing ? "停止并生成纪要" : "开始录制")
                    .font(Theme.ui(12, .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(cap.isCapturing ? AnyShapeStyle(Theme.danger500) : AnyShapeStyle(Theme.inkGrad))
            .clipShape(Capsule())
            .glow(cap.isCapturing ? Theme.danger500 : Color.black, radius: 9, opacity: 0.28)
        }
        .buttonStyle(.plain)
        .disabled(store.refining || (!cap.isCapturing && !engineReady))
        .opacity(!cap.isCapturing && !engineReady ? 0.4 : 1)
    }
}
