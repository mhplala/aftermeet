import SwiftUI

/// 顶栏常驻的录制状态条 —— 「会中转写」从一级目录降级成随处可见的状态。
/// 空闲：● 录制　检测到会议：绿色高亮　录制中：红色计时　提炼中：整理中　完成：✓ 点击查看
struct RecStrip: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var cap: CaptureService

    private enum Phase { case idle, detected, recording, refining, done }
    private var phase: Phase {
        if store.freshLiveID != nil { return .done }
        if store.refining { return .refining }
        if cap.isCapturing { return .recording }
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
            PulsingDot(color: Theme.danger500)
        case .refining:
            ProgressView().controlSize(.mini)
        case .done:
            Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundColor(.white)
        }
    }

    @ViewBuilder private var label: some View {
        switch phase {
        case .idle:
            Text("录制").font(Theme.ui(12.5, .semibold)).foregroundColor(Theme.inkSecondary)
        case .detected:
            Text("检测到会议 · 点击开始记录").font(Theme.ui(12.5, .semibold)).foregroundColor(Theme.blue700)
        case .recording:
            HStack(spacing: 7) {
                Text("录制中").font(Theme.ui(12.5, .semibold))
                Text(timeString).font(Theme.mono(12, .medium))
            }.foregroundColor(Theme.danger500)
        case .refining:
            Text("整理中…").font(Theme.ui(12.5, .semibold)).foregroundColor(Theme.inkSecondary)
        case .done:
            Text("纪要已生成 · 点击查看").font(Theme.ui(12.5, .semibold)).foregroundColor(.white)
        }
    }

    private var background: AnyShapeStyle {
        switch phase {
        case .idle, .refining: return AnyShapeStyle(Color.white.opacity(0.72))
        case .detected:        return AnyShapeStyle(Theme.blue50)
        case .recording:       return AnyShapeStyle(Theme.danger50)
        case .done:            return AnyShapeStyle(Theme.inkGrad)
        }
    }

    private var borderColor: Color {
        switch phase {
        case .idle, .refining: return Theme.borderDefault
        case .detected:        return Theme.blue500.opacity(0.4)
        case .recording:       return Theme.danger500.opacity(0.4)
        case .done:            return .clear
        }
    }

    private var glowColor: Color {
        switch phase {
        case .idle, .refining: return Color.black.opacity(0.14)
        case .detected:        return Theme.blue500.opacity(0.22)
        case .recording:       return Theme.danger500.opacity(0.30)
        case .done:            return Color.black.opacity(0.30)
        }
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
    @State private var nameEdit = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("会中 · 本地实时转写")
                .font(Theme.mono(10, .semibold)).tracking(1.0)
                .foregroundColor(Theme.inkMuted).textCase(.uppercase)

            nameRow
            if !cap.calendarSuggestion.isEmpty && nameEdit.isEmpty { suggestionRow }
            autoStartRow

            if cap.isCapturing || !cap.liveText.isEmpty { liveBox }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cap.isCapturing ? "录制中 \(timeString)" : (store.refining ? "整理中…" : "未开始"))
                        .font(Theme.ui(13, .semibold)).foregroundColor(Theme.inkPrimary)
                    Text("音频仅在本机处理 · 请确保参会者知情")
                        .font(Theme.mono(9.5)).foregroundColor(Theme.inkTertiary)
                }
                Spacer()
                controlButton
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

    private var liveBox: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(cap.liveText.isEmpty ? "正在聆听…" : cap.liveText)
                    .font(Theme.ui(12.5))
                    .foregroundColor(cap.liveText.isEmpty ? Theme.inkTertiary : Theme.inkPrimary.opacity(0.88))
                    .lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Color.clear.frame(height: 1).id("bottom")
            }
            .frame(height: 120)
            .onChange(of: cap.liveText) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
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
        .disabled(store.refining)
    }
}
