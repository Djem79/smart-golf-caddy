// ios/SmartGolfCaddy/App/RootView.swift
import GoogleSignIn
import SwiftUI

struct RootView: View {
    @State private var session = SessionViewModel()
    @State private var router = AppRouter()
    @State private var store = AppStore()

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ProgressView()
            case .signedOut:
                AuthView()
            case .signedIn:
                NavigationStack(path: $router.path) {
                    HomeView()
                        .navigationDestination(for: Route.self) { route in
                            // .id(route): смена значения Route (например, лунка 2 → 3
                            // через replaceLast) ОБЯЗАНА пересоздать экран целиком —
                            // иначе SwiftUI сохраняет старый @State (вью-модель со
                            // старым holeIndex), и удары пишутся в чужую лунку.
                            destination(for: route)
                                .id(route)
                        }
                        .navigationBarHidden(true)
                }
            }
        }
        // Приложение спроектировано под светлую палитру Fairway Elite (как веб):
        // фиксируем светлую тему, чтобы системные адаптивные цвета (текст полей
        // ввода, фон sheet) не давали белое-на-белом в тёмной теме устройства.
        .preferredColorScheme(.light)
        .environment(session)
        .environment(router)
        .environment(store)
        .task { session.start() }
        .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .roundSetup:
            RoundSetupView()
        case .hole(let roundId, let number):
            HoleTrackerView(roundId: roundId, holeNumber: number)
        case .results(let roundId):
            RoundResultsView(roundId: roundId)
        }
    }
}
