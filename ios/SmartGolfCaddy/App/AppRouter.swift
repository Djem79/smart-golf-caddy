import Foundation
import Observation

enum Route: Hashable {
    case roundSetup
    case hole(roundId: String, number: Int)
    case results(roundId: String)
    case myBag
    case courseSearch
}

enum AppTab: Hashable {
    case rounds, history, profile
}

@Observable
@MainActor
final class AppRouter {
    var selectedTab: AppTab = .rounds
    var path: [Route] = []          // стек вкладки «Раунды»
    var historyPath: [Route] = []   // стек вкладки «История»
    var profilePath: [Route] = []   // стек вкладки «Профиль»

    func push(_ route: Route) {
        path.append(route)
    }

    /// Замена вершины стека «Раундов» (лунка→лунка, лунка→итоги).
    func replaceLast(_ route: Route) {
        if path.isEmpty {
            path = [route]
        } else {
            path[path.count - 1] = route
        }
    }

    func popToRoot() {
        path.removeAll()
    }

    /// «На главную» из любого места: домой на вкладку «Раунды», все стеки чисты.
    func goHome() {
        historyPath.removeAll()
        profilePath.removeAll()
        path.removeAll()
        selectedTab = .rounds
    }

    /// «Новый раунд» из любого места: вкладка «Раунды» со стеком [настройка].
    func startNewRound() {
        historyPath.removeAll()
        profilePath.removeAll()
        path = [.roundSetup]
        selectedTab = .rounds
    }
}
