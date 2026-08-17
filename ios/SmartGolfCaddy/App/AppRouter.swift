import Foundation
import Observation

enum Route: Hashable {
    case roundSetup
    case hole(roundId: String, number: Int)
    case results(roundId: String)
}

@Observable
@MainActor
final class AppRouter {
    var path: [Route] = []

    func push(_ route: Route) {
        path.append(route)
    }

    /// Замена вершины стека — переход лунка→лунка и лунка→итоги без роста стека.
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
}
