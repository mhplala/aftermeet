import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                Sidebar()
                VStack(spacing: 0) {
                    TopBar()
                    content
                        .background(Theme.canvas)
                }
            }

            if let t = store.toast {
                ToastView(text: t)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Theme.white)
        .overlay {
            if store.showOnboarding {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.showOnboarding)
        .ignoresSafeArea()
        .task { store.startWatching() }
    }

    @ViewBuilder
    private var content: some View {
        switch store.screen {
        case .home:     HomeScreen()
        case .live:     LiveScreen()
        case .history:  HistoryScreen()
        case .detail:   DetailScreen()
        case .todos:    TodosScreen()
        case .followup: FollowupScreen()
        case .weekly:   WeeklyScreen()
        case .daily:    DailyScreen()
        }
    }
}
