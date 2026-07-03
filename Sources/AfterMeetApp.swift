import SwiftUI

@main
struct AfterMeetApp: App {
    @StateObject private var store = AppStore()

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
