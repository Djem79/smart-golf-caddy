// ios/SmartGolfCaddy/App/RootView.swift
import GoogleSignIn
import SwiftUI

struct RootView: View {
    @State private var session = SessionViewModel()
    @State private var router = AppRouter()
    @State private var store = AppStore()
    @State private var localeManager = LocaleManager.shared

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ProgressView()
            case .signedOut:
                AuthView()
            case .signedIn:
                TabView(selection: $router.selectedTab) {
                    NavigationStack(path: $router.path) {
                        HomeView()
                            .navigationDestination(for: Route.self) { route in
                                // .id(route): смена значения Route обязана пересоздать
                                // экран (урок 2а: иначе старый @State пишет в чужую лунку).
                                RouteDestinationView(route: route).id(route)
                            }
                            .toolbar(.hidden, for: .navigationBar)
                    }
                    .tabItem { Label(localeManager.t.bottomNav.rounds, systemImage: "figure.golf") }
                    .tag(AppTab.rounds)

                    NavigationStack(path: $router.historyPath) {
                        HistoryView()
                            .navigationDestination(for: Route.self) { route in
                                RouteDestinationView(route: route).id(route)
                            }
                    }
                    .tabItem { Label(localeManager.t.bottomNav.history, systemImage: "clock.arrow.circlepath") }
                    .tag(AppTab.history)

                    NavigationStack(path: $router.profilePath) {
                        ProfileView()
                            .navigationDestination(for: Route.self) { route in
                                RouteDestinationView(route: route).id(route)
                            }
                    }
                    .tabItem { Label(localeManager.t.bottomNav.profile, systemImage: "person.crop.circle") }
                    .tag(AppTab.profile)
                }
                .tint(DSColor.primary)
            }
        }
        // Приложение спроектировано под светлую палитру Fairway Elite (как веб):
        // фиксируем светлую тему, чтобы системные адаптивные цвета (текст полей
        // ввода, фон sheet) не давали белое-на-белом в тёмной теме устройства.
        .preferredColorScheme(.light)
        .environment(session)
        .environment(router)
        .environment(store)
        .environment(localeManager)
        .task { session.start() }
        .onOpenURL { url in
            // smartgolfcaddy://join/ABC234 или https://<host>/join/ABC234
            if let code = Self.joinCode(from: url) {
                router.selectedTab = .rounds
                router.path = [.joinGame(code: code)]
                return
            }
            GIDSignIn.sharedInstance.handle(url)
        }
        .onChange(of: session.state) { _, state in
            // Повторный вход (в т.ч. другим аккаунтом) начинается с чистого Home.
            if state == .signedOut {
                router.goHome()
                store.selectedCourse = nil
                store.prefillCourseName = nil
                store.lastClubUsed = "Driver"
            }
        }
    }

    /// Извлекает код лобби из join-ссылки (схема приложения или веб-ссылка).
    static func joinCode(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        if url.scheme == "smartgolfcaddy", url.host == "join", let code = parts.first {
            return code
        }
        if parts.count >= 2, parts[parts.count - 2] == "join" {
            return parts[parts.count - 1]
        }
        return nil
    }
}

struct RouteDestinationView: View {
    let route: Route

    var body: some View {
        switch route {
        case .roundSetup:
            RoundSetupView()
        case .hole(let roundId, let number):
            HoleTrackerView(roundId: roundId, holeNumber: number)
        case .results(let roundId):
            RoundResultsView(roundId: roundId)
        case .myBag:
            MyBagView()
        case .courseSearch:
            CourseSearchView()
        case .lobby(let roundId):
            GroupLobbyView(roundId: roundId)
        case .joinGame(let code):
            JoinGameView(code: code)
        case .leaderboard(let roundId):
            LeaderboardView(roundId: roundId)
        }
    }
}
