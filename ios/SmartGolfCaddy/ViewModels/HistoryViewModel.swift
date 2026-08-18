import Foundation
import Observation

@Observable
@MainActor
final class HistoryViewModel {
    var rounds: [Round] = []
    var loading = true
    var loadError = false

    func load(userId: String) async {
        loading = true
        loadError = false
        defer { loading = false }
        do {
            let all = try await RoundsService.getUserRounds(userId: userId)
            rounds = all.filter { $0.status == .finished }
        } catch {
            loadError = true
        }
    }
}
