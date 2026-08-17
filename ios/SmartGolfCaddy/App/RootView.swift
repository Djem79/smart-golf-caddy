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
                            destination(for: route)
                        }
                        .navigationBarHidden(true)
                }
            }
        }
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
