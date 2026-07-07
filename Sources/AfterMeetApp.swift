import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // 录制中退出：杀掉常驻 whisper-server，别留 ~1GB 孤儿进程
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/pkill"),
                             arguments: ["-9", "-f", "whisper-server.*8178"])
    }
}

@main
struct AfterMeetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()

    init() {
        signal(SIGPIPE, SIG_IGN)   // 子进程管道断裂返回 EPIPE，而不是直接杀掉 app
        // 上次异常退出可能留下孤儿 whisper-server，启动即清（不等到下次录制）
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/pkill"),
                             arguments: ["-9", "-f", "whisper-server.*8178"])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(store.capture)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1240, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarPanel(capture: store.capture)
                .environmentObject(store)
        } label: {
            MenuBarLabel(capture: store.capture)
        }
        .menuBarExtraStyle(.window)
    }
}
