// ios/SmartGolfCaddy/ViewModels/GroupLobbyViewModel.swift
// Порт GroupLobby.tsx: живая подписка на лобби, старт хостом, выход.
import Foundation
import Observation

@Observable
@MainActor
final class GroupLobbyViewModel {
    var round: Round?
    var loadError: String?
    var errorMessage: String?
    var starting = false

    private var roundId: String?
    private var unsubscribe: (() -> Void)?

    var isHost: Bool {
        guard let round, let uid = AuthService.currentUserId else { return false }
        return round.hostId == uid
    }

    /// Участники в порядке playerIds (тот, кого нет в players-мапе, пропускается).
    var players: [(uid: String, info: PlayerInfo)] {
        guard let round else { return [] }
        return round.playerIds.compactMap { uid in
            round.players[uid].map { (uid, $0) }
        }
    }

    func start(roundId: String) {
        guard unsubscribe == nil else { return }
        self.roundId = roundId
        unsubscribe = RoundsService.subscribeToRound(
            roundId: roundId,
            onChange: { [weak self] round in self?.round = round },
            onError: { [weak self] _ in
                self?.loadError = "Не удалось загрузить лобби. Возможно, вы не участник этого раунда или пропала связь."
            }
        )
    }

    func startRound() async {
        guard let roundId, isHost, !starting else { return }
        starting = true
        errorMessage = nil
        defer { starting = false }
        do {
            try await RoundsService.startRound(roundId: roundId)
            // Подписка сама переведёт всех на лунку 1 при status == .active
        } catch {
            errorMessage = "Не удалось запустить раунд. Попробуйте ещё раз."
        }
    }

    @discardableResult
    func leave() async -> Bool {
        guard let roundId, let uid = AuthService.currentUserId, let round else { return false }
        do {
            try await RoundsService.leaveLobby(
                roundId: roundId, userId: uid, currentPlayerIds: round.playerIds
            )
            return true
        } catch {
            // Гонка: playerIds на сервере уже изменились (кто-то другой вышел
            // или подключился) — подписка сама подтянет актуальный список,
            // повторный тап сработает.
            errorMessage = "Не удалось выйти из лобби. Обновите экран и попробуйте ещё раз."
            return false
        }
    }

    @MainActor deinit {
        unsubscribe?()
    }
}
