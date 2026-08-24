// ios/SmartGolfCaddyTests/WatchBridgeTests.swift
// Тесты WatchBridge.applyBatch (Fix 4, живое ревью Task 4) — это код,
// который пишет на сервер, и оба CRITICAL живого ревью (Fix 1, Fix 3)
// живут именно в нём. Зависимости инжектируются через init (как
// ShotRangefinder.init(storeURL:fixProvider:)) — без реального
// Firebase/WatchConnectivity.
import XCTest
@testable import SmartGolfCaddy

final class WatchBridgeTests: XCTestCase {

    private func makeRound(
        totalHoles: Int = 4,
        uid: String = "user-1",
        clubsForUser: [Int: [String]] = [:],
        distancesForUser: [Int: [Int]] = [:]
    ) -> Round {
        var holes: [[String: Any]] = []
        for n in 1...totalHoles {
            var shots: [String: [String: Any]] = [:]
            if let clubs = clubsForUser[n] {
                var shotDict: [String: Any] = ["count": clubs.count, "clubs": clubs]
                if let distances = distancesForUser[n] {
                    shotDict["distances"] = distances
                }
                shots[uid] = shotDict
            }
            holes.append(["holeNumber": n, "par": 4, "distanceMeters": 300, "shots": shots])
        }
        return Round(id: "r1", data: [
            "courseId": "c", "courseName": "Test", "totalHoles": totalHoles,
            "lobbyCode": "ABC234", "status": "active", "hostId": uid,
            "players": [uid: ["name": "A", "avatar": "", "totalScore": 0, "scoreDiff": 0]],
            "playerIds": [uid], "holes": holes,
            "startedAt": Date(), "createdAt": Date(),
        ])!
    }

    private func makeBatch(roundId: String = "r1", holeNumber: Int = 1, clubs: [String]) -> WatchShotBatch {
        WatchShotBatch(roundId: roundId, entries: [WatchShotEntry(holeNumber: holeNumber, clubs: clubs, recordedAt: Date())])
    }

    /// Простой захватываемый по ссылке контейнер для тестов, которым нужно
    /// смоделировать эволюцию "серверного" состояния между двумя вызовами
    /// applyBatch (идемпотентность повторной доставки).
    private final class FakeServerState: @unchecked Sendable {
        var clubs: [String] = []
    }

    // MARK: - Fix 1 (живое ревью): pendingShot приоритетнее серверного
    // раунда — иначе батч с часов затирает НЕОТПРАВЛЕННЫЙ удар телефона.

    func testUsesPendingShotAsBaseWhenPresent() async {
        var recordedClubs: [String]?
        var recordedDistances: [Int]?
        let bridge = WatchBridge(
            currentUserIdProvider: { "user-1" },
            // Раунд (сервер/кэш) ещё НЕ знает "Driver" — офлайн-запись
            // телефона не долетела до Firestore. Без Fix 1 это привело бы
            // к fullClubs = ["7 Iron"], теряя Driver безвозвратно.
            roundProvider: { _ in self.makeRound() },
            pendingShotProvider: { roundId, holeIndex, uid in
                PendingShot(roundId: roundId, holeIndex: holeIndex, targetUid: uid, clubs: ["Driver"], distances: [230], updatedAt: 0)
            },
            shotRecorder: { _, _, _, clubs, distances in
                recordedClubs = clubs
                recordedDistances = distances
                return .synced
            }
        )
        await bridge.applyBatch(makeBatch(holeNumber: 1, clubs: ["7 Iron"]))
        XCTAssertEqual(recordedClubs, ["Driver", "7 Iron"], "Driver из ShotQueue.pendingShot не должен быть потерян")
        XCTAssertEqual(recordedDistances, [230, 0])
    }

    func testFallsBackToServerRoundWhenNoPendingShot() async {
        var recordedClubs: [String]?
        let bridge = WatchBridge(
            currentUserIdProvider: { "user-1" },
            roundProvider: { _ in self.makeRound(clubsForUser: [1: ["Driver"]]) },
            pendingShotProvider: { _, _, _ in nil },
            shotRecorder: { _, _, _, clubs, _ in recordedClubs = clubs; return .synced }
        )
        await bridge.applyBatch(makeBatch(holeNumber: 1, clubs: ["7 Iron"]))
        XCTAssertEqual(recordedClubs, ["Driver", "7 Iron"], "без pending-записи используется серверный resolvedClubs")
    }

    func testPendingShotDistancesPaddedToMatchClubsCount() async {
        // distances может отставать от clubs по длине (легаси/частичная
        // запись) — база должна восстанавливать инвариант равной длины
        // ДО дописывания хвоста с часов, а не просто взять distances как есть.
        var recordedDistances: [Int]?
        let bridge = WatchBridge(
            currentUserIdProvider: { "user-1" },
            roundProvider: { _ in self.makeRound() },
            pendingShotProvider: { roundId, holeIndex, uid in
                PendingShot(roundId: roundId, holeIndex: holeIndex, targetUid: uid, clubs: ["Driver", "3 Wood"], distances: [230], updatedAt: 0)
            },
            shotRecorder: { _, _, _, _, distances in recordedDistances = distances; return .synced }
        )
        await bridge.applyBatch(makeBatch(holeNumber: 1, clubs: ["Putter"]))
        XCTAssertEqual(recordedDistances, [230, 0, 0], "distances дополнены нулём до длины pending.clubs, затем ещё нулём под хвост")
    }

    // MARK: - Fix 3 (живое ревью): исход .rejected — квитанция с accepted: false

    func testRejectedOutcomeSendsUnacceptedReceipt() async {
        var sentReceipt: WatchShotReceipt?
        let bridge = WatchBridge(
            currentUserIdProvider: { "user-1" },
            roundProvider: { _ in self.makeRound() },
            pendingShotProvider: { _, _, _ in nil },
            shotRecorder: { _, _, _, _, _ in .rejected(NSError(domain: "test", code: 1)) },
            receiptSender: { sentReceipt = $0 }
        )
        await bridge.applyBatch(makeBatch(holeNumber: 1, clubs: ["Driver"]))
        XCTAssertEqual(sentReceipt?.entries.first?.accepted, false)
        XCTAssertEqual(sentReceipt?.entries.first?.acceptedCount, 1, "часы всё равно снимают слот целиком — ретраить бессмысленно")
    }

    func testAcceptedOutcomesSendAcceptedReceipt() async {
        var sentReceipt: WatchShotReceipt?
        let bridge = WatchBridge(
            currentUserIdProvider: { "user-1" },
            roundProvider: { _ in self.makeRound() },
            pendingShotProvider: { _, _, _ in nil },
            shotRecorder: { _, _, _, _, _ in .synced },
            receiptSender: { sentReceipt = $0 }
        )
        await bridge.applyBatch(makeBatch(holeNumber: 1, clubs: ["Driver"]))
        XCTAssertEqual(sentReceipt?.entries.first?.accepted, true)
    }

    func testMixedAcceptedAndRejectedEntriesInOneBatch() async {
        var sentReceipt: WatchShotReceipt?
        let bridge = WatchBridge(
            currentUserIdProvider: { "user-1" },
            roundProvider: { _ in self.makeRound(totalHoles: 2) },
            pendingShotProvider: { _, _, _ in nil },
            shotRecorder: { _, holeIndex, _, _, _ in holeIndex == 0 ? .synced : .rejected(NSError(domain: "t", code: 1)) },
            receiptSender: { sentReceipt = $0 }
        )
        let batch = WatchShotBatch(roundId: "r1", entries: [
            WatchShotEntry(holeNumber: 1, clubs: ["Driver"], recordedAt: Date()),
            WatchShotEntry(holeNumber: 2, clubs: ["Putter"], recordedAt: Date()),
        ])
        await bridge.applyBatch(batch)
        let byHole = Dictionary(uniqueKeysWithValues: (sentReceipt?.entries ?? []).map { ($0.holeNumber, $0.accepted) })
        XCTAssertEqual(byHole[1], true)
        XCTAssertEqual(byHole[2], false)
    }

    // MARK: - Fix 4 (живое ревью): пустой/чужой раунд, неавторизованный часовой носитель

    func testUnknownRoundSkipsWriteAndReceipt() async {
        var recorderCalled = false
        var sentReceipt: WatchShotReceipt?
        let bridge = WatchBridge(
            currentUserIdProvider: { "user-1" },
            roundProvider: { _ in nil },
            pendingShotProvider: { _, _, _ in nil },
            shotRecorder: { _, _, _, _, _ in recorderCalled = true; return .synced },
            receiptSender: { sentReceipt = $0 }
        )
        await bridge.applyBatch(makeBatch(holeNumber: 1, clubs: ["Driver"]))
        XCTAssertFalse(recorderCalled, "без знания текущего состояния раунда писать нельзя")
        XCTAssertNil(sentReceipt, "без записи подтверждать часам нечего — они повторят на следующем flush")
    }

    func testRoundFetchThrowingSkipsWriteAndReceipt() async {
        var recorderCalled = false
        let bridge = WatchBridge(
            currentUserIdProvider: { "user-1" },
            roundProvider: { _ in throw NSError(domain: "offline", code: -1) },
            pendingShotProvider: { _, _, _ in nil },
            shotRecorder: { _, _, _, _, _ in recorderCalled = true; return .synced }
        )
        await bridge.applyBatch(makeBatch(holeNumber: 1, clubs: ["Driver"]))
        XCTAssertFalse(recorderCalled)
    }

    func testNoAuthenticatedUserSkipsWriteAndReceipt() async {
        var recorderCalled = false
        let bridge = WatchBridge(
            currentUserIdProvider: { nil },
            roundProvider: { _ in self.makeRound() },
            pendingShotProvider: { _, _, _ in nil },
            shotRecorder: { _, _, _, _, _ in recorderCalled = true; return .synced }
        )
        await bridge.applyBatch(makeBatch(holeNumber: 1, clubs: ["Driver"]))
        XCTAssertFalse(recorderCalled)
    }

    func testOutOfRangeHoleIsSkippedButOthersStillApplied() async {
        var recordedHoleIndices: [Int] = []
        let bridge = WatchBridge(
            currentUserIdProvider: { "user-1" },
            roundProvider: { _ in self.makeRound(totalHoles: 2) },
            pendingShotProvider: { _, _, _ in nil },
            shotRecorder: { _, holeIndex, _, _, _ in recordedHoleIndices.append(holeIndex); return .synced }
        )
        let batch = WatchShotBatch(roundId: "r1", entries: [
            WatchShotEntry(holeNumber: 1, clubs: ["Driver"], recordedAt: Date()),
            WatchShotEntry(holeNumber: 99, clubs: ["Putter"], recordedAt: Date()),
        ])
        await bridge.applyBatch(batch)
        XCTAssertEqual(recordedHoleIndices, [0], "лунка за пределами раунда пропущена, а не роняет весь батч")
    }

    // MARK: - Fix 4: идемпотентность повторной доставки одного батча

    func testRepeatingSameBatchIsIdempotentAgainstUpdatedServerState() async {
        let store = FakeServerState()
        let bridge = WatchBridge(
            currentUserIdProvider: { "user-1" },
            roundProvider: { _ in self.makeRound(clubsForUser: store.clubs.isEmpty ? [:] : [1: store.clubs]) },
            pendingShotProvider: { _, _, _ in nil },
            shotRecorder: { _, _, _, clubs, _ in store.clubs = clubs; return .synced }
        )
        let batch = makeBatch(holeNumber: 1, clubs: ["Driver"])

        await bridge.applyBatch(batch)
        XCTAssertEqual(store.clubs, ["Driver"])

        // Повторная доставка ТОГО ЖЕ батча (throttle-таймаут на часах гонится
        // с запоздавшей оригинальной отправкой — см. WatchShotQueue.inFlightTimeout) —
        // суффиксная проверка узнаёт, что хвост уже применён, и не дублирует.
        await bridge.applyBatch(batch)
        XCTAssertEqual(store.clubs, ["Driver"], "повтор одного и того же батча не должен плодить дубликат")
    }

    func testGrowingTailAfterPreviousBatchAppendsOnlyNewPortion() async {
        // Нормальный (НЕ дублирующий) случай: второй батч содержит РОВНО
        // новый хвост (как его строит WatchShotQueue после того, как
        // markConfirmed срезал подтверждённый префикс) — суффиксная
        // проверка не должна ложно сработать и потерять новый удар.
        let store = FakeServerState()
        let bridge = WatchBridge(
            currentUserIdProvider: { "user-1" },
            roundProvider: { _ in self.makeRound(clubsForUser: store.clubs.isEmpty ? [:] : [1: store.clubs]) },
            pendingShotProvider: { _, _, _ in nil },
            shotRecorder: { _, _, _, clubs, _ in store.clubs = clubs; return .synced }
        )
        await bridge.applyBatch(makeBatch(holeNumber: 1, clubs: ["Driver"]))
        XCTAssertEqual(store.clubs, ["Driver"])

        await bridge.applyBatch(makeBatch(holeNumber: 1, clubs: ["7 Iron"]))
        XCTAssertEqual(store.clubs, ["Driver", "7 Iron"], "новый (не повторяющийся) хвост дописывается как обычно")
    }
}
