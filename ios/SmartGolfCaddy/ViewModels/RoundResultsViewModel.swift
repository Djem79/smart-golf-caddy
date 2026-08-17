// ios/SmartGolfCaddy/ViewModels/RoundResultsViewModel.swift
import Foundation
import Observation

@Observable
@MainActor
final class RoundResultsViewModel {
    var round: Round?
    var loadError: String?
    private var unsubscribe: (() -> Void)?

    func start(roundId: String) {
        guard unsubscribe == nil else { return }
        unsubscribe = RoundsService.subscribeToRound(
            roundId: roundId,
            onChange: { [weak self] round in self?.round = round },
            onError: { [weak self] _ in
                self?.loadError = "Не удалось загрузить итоги. Проверьте связь."
            }
        )
    }

    @MainActor deinit {
        unsubscribe?()
    }
}
