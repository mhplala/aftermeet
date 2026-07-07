import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                Sidebar()
                VStack(spacing: 0) {
                    TopBar()
                        .zIndex(10)      // 搜索结果下拉要压住内容区
                    content
                        .background(Theme.canvas)   // 工作区纯白
                }
            }
            .background(AmbientBackground())        // 光晕只从框架层透出来

            if let t = store.toast {
                ToastView(text: t)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if store.showOnboarding {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.showOnboarding)
        .ignoresSafeArea()
        .task { store.startWatching() }
        .background {   // ⌘[ 返回
            Button("") { store.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .opacity(0)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.screen {
        case .home:     HomeScreen()
        case .library:  LibraryScreen()
        case .detail:   DetailScreen()
        case .todos:    TodosScreen()
        case .followup: FollowupScreen()
        case .weekly:   WeeklyScreen()
        case .daily:    DailyScreen()
        }
    }
}
