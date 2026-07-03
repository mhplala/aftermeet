import SwiftUI

struct LiveScreen: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var cap: CaptureService
    @State private var nameEdit = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Overline("会中 · 本地实时转写", tracking: 1.2).padding(.bottom, 8)
                Text("会中实时转写")
                    .font(Theme.display(36, .medium)).tracking(-0.7).foregroundColor(Theme.inkPrimary)
                Text("本地截系统音频、端上转写——音频不出网。结束后自动提炼成纪要。")
                    .font(Theme.display(15, .regular)).italic()
                    .foregroundColor(Theme.inkSecondary).padding(.top, 8).padding(.bottom, 22)
                    .fixedSize(horizontal: false, vertical: true)

                if store.meetingActive && !cap.isCapturing && !store.autoStart {
                    detectBanner.padding(.bottom, 12)
                }
                meetingNameRow.padding(.bottom, 12)
                autoStartRow.padding(.bottom, 12)
                controlCard.padding(.bottom, 16)
                transcriptCard
                consentNote.padding(.top, 14)
            }
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
    }

    private var detectBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 16)).foregroundColor(Theme.accent)
            Text("检测到麦克风启用,可能正在开会").font(Theme.ui(13, .medium)).foregroundColor(Theme.inkPrimary)
            Spacer()
            Button { Task { await cap.start() } } label: {
                Text("开始记录").font(Theme.ui(12.5, .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Theme.accent).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.accentSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
    }

    private var meetingNameRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "pencil.and.list.clipboard").font(.system(size: 13)).foregroundColor(Theme.inkTertiary)
                Text("会议").font(Theme.ui(13, .medium)).foregroundColor(Theme.inkSecondary)
                TextField("给这场会起个名（停录后豆包也会按内容补一个）", text: $nameEdit)
                    .textFieldStyle(.plain).font(Theme.ui(14)).foregroundColor(Theme.inkPrimary)
                    .onSubmit { cap.setMeetingName(nameEdit) }
                if !nameEdit.isEmpty {
                    Button { cap.setMeetingName(nameEdit) } label: {
                        Text("确定").font(Theme.ui(12, .semibold)).foregroundColor(Theme.accent)
                    }.buttonStyle(.plain)
                }
            }
            if !cap.calendarSuggestion.isEmpty && nameEdit.isEmpty {
                HStack(spacing: 8) {
                    Text("日程里这会儿是").font(Theme.mono(10.5)).foregroundColor(Theme.inkTertiary)
                    Button { nameEdit = cap.calendarSuggestion; cap.setMeetingName(cap.calendarSuggestion) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar").font(.system(size: 10))
                            Text(cap.calendarSuggestion).font(Theme.ui(11.5, .medium))
                        }
                        .foregroundColor(Theme.blue700)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Theme.blue50).clipShape(Capsule())
                    }.buttonStyle(.plain)
                    Text("· 不对就直接上面填").font(Theme.mono(10.5)).foregroundColor(Theme.inkTertiary)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
        .hairline(Theme.borderWhisper, radius: Theme.rMD)
        .onChange(of: cap.meetingName) { _, new in if !new.isEmpty && nameEdit.isEmpty { nameEdit = new } }
    }

    private var autoStartRow: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { store.autoStart }, set: { store.setAutoStart($0) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
            VStack(alignment: .leading, spacing: 1) {
                Text("检测到会议自动开始记录").font(Theme.ui(13, .medium)).foregroundColor(Theme.inkPrimary)
                Text(store.autoStart ? "麦克风一活就自动录,无需点击" : "默认:检测到只提示,由你一键开始")
                    .font(Theme.mono(10.5)).foregroundColor(Theme.inkTertiary)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(store.meetingActive ? Theme.green500 : Theme.inkMuted).frame(width: 7, height: 7)
                Text(store.meetingActive ? "麦克风活跃" : "无会议")
                    .font(Theme.mono(10.5)).foregroundColor(Theme.inkTertiary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
        .hairline(Theme.borderWhisper, radius: Theme.rMD)
    }

    private var controlCard: some View {
        Card(padding: 20) {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(cap.isCapturing ? Theme.danger50 : Theme.warmWhite2).frame(width: 46, height: 46)
                    Circle().fill(cap.isCapturing ? Theme.danger500 : Theme.inkMuted).frame(width: 14, height: 14)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(cap.isCapturing ? "录制中" : (store.refining ? "整理中…" : "未开始"))
                        .font(Theme.display(17, .medium)).foregroundColor(Theme.inkPrimary)
                    Text(cap.status).font(Theme.mono(11)).foregroundColor(Theme.inkTertiary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(timeString).font(Theme.mono(20, .medium)).foregroundColor(Theme.inkPrimary)
                button
            }
        }
    }

    private var button: some View {
        Button {
            if cap.isCapturing {
                Task {
                    let text = await cap.stop()
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4 {
                        store.ingestLive(transcript: text, durationSec: cap.elapsed)
                    }
                }
            } else {
                Task { await cap.start() }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: cap.isCapturing ? "stop.fill" : "record.circle")
                Text(cap.isCapturing ? "停止并生成纪要" : "开始录制")
            }
            .font(Theme.ui(13, .semibold)).foregroundColor(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(cap.isCapturing ? Theme.danger500 : Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rMD, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(store.refining)
    }

    private var transcriptCard: some View {
        Card(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("实时转写").font(Theme.display(16, .medium)).foregroundColor(Theme.inkPrimary)
                    if !cap.liveText.isEmpty {
                        Text("\(cap.liveText.count) 字").font(Theme.mono(10.5)).foregroundColor(Theme.inkTertiary)
                    }
                    Spacer()
                    if cap.isCapturing {
                        Text("Whisper · 本地").font(Theme.mono(10.5)).foregroundColor(Theme.green700)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.green50).clipShape(Capsule())
                    }
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(cap.liveText.isEmpty
                             ? (cap.isCapturing ? "（听着呢…说点什么）" : "点「开始录制」，对着会议或播放一段语音。")
                             : cap.liveText)
                            .font(Theme.ui(14))
                            .foregroundColor(cap.liveText.isEmpty ? Theme.inkTertiary : Theme.inkPrimary.opacity(0.88))
                            .lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .frame(height: 300)
                    .onChange(of: cap.liveText) { _, _ in
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }
        }
    }

    private var consentNote: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle").font(.system(size: 12)).foregroundColor(Theme.inkTertiary)
                Text("录制对其他参会者不可见。请确保他们知情——是否声明由你决定。")
                    .font(Theme.ui(12)).foregroundColor(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            if !cap.savedPath.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.fill").font(.system(size: 11)).foregroundColor(Theme.green700)
                    Text("实时存档（边转边写，崩了也不丢）：\(cap.savedPath)")
                        .font(Theme.mono(10.5)).foregroundColor(Theme.inkTertiary)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Spacer()
                }
            }
        }
    }

    private var timeString: String {
        String(format: "%02d:%02d", cap.elapsed / 60, cap.elapsed % 60)
    }
}
