// ios/SmartGolfCaddy/ViewModels/LeaderboardViewModel.swift
// Живая таблица результатов группового раунда — подписка на тот же
// документ, что HoleTracker/RoundResults; по образцу RoundResultsViewModel.
import Foundation
import Observation

@Observable
@MainActor
final class LeaderboardViewModel {
    var round: Round?
    var loadError: String?
    private var unsubscribe: (() -> Void)?

    func start(roundId: String) {
        guard unsubscribe == nil else { return }
        unsubscribe = RoundsService.subscribeToRound(
            roundId: roundId,
            onChange: { [weak self] round in self?.round = round },
            onError: { [weak self] _ in
                self?.loadError = AppLocaleStore.strings.leaderboard.loadError
            }
        )
    }

    @MainActor deinit {
        unsubscribe?()
    }
}
