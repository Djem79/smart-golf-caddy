import Foundation
import Observation

@Observable
@MainActor
final class HomeViewModel {
    var activeRound: Round?
    var recentFinished: [Round] = []
    var loadError = false
    var loading = false

    func load(userId: String) async {
        loading = true
        loadError = false
        defer { loading = false }
        do {
            // Окно 10: Home показывает 3 последних finished + ищет незавершённый.
            let rounds = try await RoundsService.getUserRounds(userId: userId, limitTo: 10)
            recentFinished = Array(rounds.filter { $0.status == .finished }.prefix(3))
            activeRound = rounds.first { $0.status == .active || $0.status == .lobby }
        } catch {
            loadError = true
        }
    }

    /// Первая лунка без ударов игрока; если все сыграны — последняя.
    static func resumeHoleNumber(round: Round, userId: String) -> Int {
        if let index = round.holes.firstIndex(where: { ($0.shots[userId]?.count ?? 0) == 0 }) {
            return index + 1
        }
        return round.totalHoles
    }

    static func resumeSubtitle(round: Round, userId: String) -> String {
        let played = round.holes.filter { ($0.shots[userId]?.count ?? 0) > 0 }.count
        return "Пройдено \(played) из \(round.totalHoles)"
    }
}
