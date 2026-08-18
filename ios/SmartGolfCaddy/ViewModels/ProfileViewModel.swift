import Foundation
import Observation

@Observable
@MainActor
final class ProfileViewModel {
    var rounds: [Round] = []
    var loadError = false

    func load(userId: String) async {
        loadError = false
        do {
            rounds = try await RoundsService.getUserRounds(userId: userId)
        } catch {
            loadError = true
        }
    }
}
