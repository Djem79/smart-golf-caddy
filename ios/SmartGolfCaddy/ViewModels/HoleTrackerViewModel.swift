// ios/SmartGolfCaddy/ViewModels/HoleTrackerViewModel.swift
// Порт HoleTracker.tsx: оптимистичный оверлей поверх Firestore + офлайн-
// очереди. Слот "\(holeIndex):\(userId)" не даёт оверлею одной лунки/
// игрока протечь в другую; awaitingKey гасит оверлей, как только сервер
// отэхоил ровно те же клюшки.
import Foundation
import Observation

@Observable
@MainActor
final class HoleTrackerViewModel {

    struct Optimistic: Equatable {
        var slot: String
        var clubs: [String]
        var awaitingKey: String
    }

    let roundId: String
    let holeIndex: Int
    let userId: String

    var round: Round?
    var loadError: String?
    var saveError: String?
    var saving = false
    var finishing = false
    var hasQueuedShots = false
    var optimistic: Optimistic?

    private var unsubscribe: (() -> Void)?
    private var queueObserver: NSObjectProtocol?

    init(roundId: String, holeIndex: Int, userId: String) {
        self.roundId = roundId
        self.holeIndex = holeIndex
        self.userId = userId
    }

    var slotKey: String { "\(holeIndex):\(userId)" }
    var hole: HoleConfig? {
        guard let round, round.holes.indices.contains(holeIndex) else { return nil }
        return round.holes[holeIndex]
    }
    var isHost: Bool { round?.hostId == userId }

    func start() {
        refreshQueueBadge()
        queueObserver = NotificationCenter.default.addObserver(
            forName: .shotQueueDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshQueueBadge() }
        }
        unsubscribe = RoundsService.subscribeToRound(
            roundId: roundId,
            onChange: { [weak self] round in self?.round = round },
            onError: { [weak self] _ in
                self?.loadError = "Не удалось загрузить раунд. Проверьте связь."
            }
        )
    }

    /// Дерив отображаемой серии (порт myClubs из HoleTracker.tsx):
    /// optimistic пока «впереди» сервера → pending из очереди → server.
    func displayedClubs(serverClubs: [String], pendingClubs: [String]?) -> [String] {
        if let optimistic, optimistic.slot == slotKey,
           serverClubs.joined(separator: "|") != optimistic.awaitingKey {
            return optimistic.clubs
        }
        return pendingClubs ?? serverClubs
    }

    var currentClubs: [String] {
        let server = hole?.shots[userId]?.resolvedClubs ?? []
        let pending = ShotQueue.shared.pendingShot(
            roundId: roundId, holeIndex: holeIndex, targetUid: userId
        )?.clubs
        return displayedClubs(serverClubs: server, pendingClubs: pending)
    }

    /// Возвращает true при .synced/.queued (веб ставит lastClubUsed только на
    /// успешной мутации), false при .rejected (rollback-ветка).
    @discardableResult
    func save(_ clubs: [String]) async -> Bool {
        saving = true
        saveError = nil
        optimistic = Optimistic(slot: slotKey, clubs: clubs,
                                awaitingKey: clubs.joined(separator: "|"))
        defer { saving = false }
        let outcome = await ShotQueue.shared.recordShotQueued(
            roundId: roundId, holeIndex: holeIndex, targetUid: userId, clubs: clubs
        )
        if case .rejected = outcome {
            saveError = "Не удалось сохранить удар."
            if optimistic?.slot == slotKey { optimistic = nil }  // rollback слота
            refreshQueueBadge()
            return false
        }
        refreshQueueBadge()
        return true
    }

    func finish() async -> Bool {
        guard !finishing else { return false }
        finishing = true
        saveError = nil
        defer { finishing = false }
        do {
            try await RoundsService.finishRound(roundId: roundId)
            return true
        } catch {
            saveError = "Не удалось завершить раунд. Попробуйте ещё раз."
            return false
        }
    }

    func saveHoleConfig(par: Int?, distanceMeters: Int?) async -> Bool {
        do {
            try await RoundsService.updateHoleConfig(
                roundId: roundId, holeIndex: holeIndex,
                par: par, distanceMeters: distanceMeters
            )
            return true
        } catch {
            saveError = "Не удалось сохранить параметры лунки."
            return false
        }
    }

    private func refreshQueueBadge() {
        hasQueuedShots = ShotQueue.shared.pendingCount(roundId: roundId) > 0
    }

    @MainActor deinit {
        unsubscribe?()
        if let queueObserver { NotificationCenter.default.removeObserver(queueObserver) }
    }
}
