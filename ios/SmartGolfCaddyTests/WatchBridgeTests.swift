// ios/SmartGolfCaddyTests/WatchBridgeTests.swift
// Тесты WatchBridge.applyBatch — это код, который пишет на сервер, и три
// из четырёх CRITICAL/IMPORTANT живого ревью Task 4 (Fix 1, Fix 3, Fix 5,
// плюс Fix 8 поверх Fix 5) живут именно в нём. Зависимости инжектируются
// через init (как ShotRangefinder.init(storeURL:fixProvider:)) — без
// реального Firebase/WatchConnectivity.
//
// lastAppliedSequenceProvider/sequenceRecorder ВСЕГДА инжектируются явно
// (никогда не дефолт, который бьёт в WatchBatchSequenceLedger.shared) —
// дефолт делит один файл на диске со ВСЕМИ тестами процесса; большинство
// тестов здесь используют один и тот же roundId/holeNumber/uid/sequence/
// installId по умолчанию (makeBatch), и общий файл дал бы одному тесту
// увидеть "уже применено" из-за состояния, оставленного другим.
// noOpLastApplied/noOpSequenceRecorder (везде, кроме тестов на сам Fix 5/8)
// — всегда "ничего ещё не применялось".
import XCTest
@testable import SmartGolfCaddy

final class WatchBridgeTests: XCTestCase {

    /// Всегда "ничего не применялось" и никогда ничего не запоминает —
    /// безопасный дефолт для тестов, не проверяющих сам механизм sequence-
    /// дедупликации (Fix 1/Fix 3/общий Fix 4).
    private let noOpLastApplied: (String, Int, String, String) -> Int? = { _, _, _, _ in nil }
    private let noOpSequenceRecorder: (String, Int, String, String, Int) -> Void = { _, _, _, _, _ in }

    /// Простой in-memory журнал sequence — для тестов, которые САМИ
    /// проверяют Fix 5/Fix 8 (нужно реальное состояние между двумя
    /// вызовами applyBatch, но БЕЗ файла на диске и БЕЗ общего .shared).
    private final class FakeSequenceLedger: @unchecked Sendable {
        private var applied: [String: Int] = [:]
        private let lock = NSLock()
        private func key(_ roundId: String, _ holeIndex: Int, _ uid: String, _ installId: String) -> String {
            "\(roundId):\(holeIndex):\(uid):\(installId)"
        }
        func lastApplied(_ roundId: String, _ holeIndex: Int, _ uid: String, _ installId: String) -> Int? {
            lock.lock(); defer { lock.unlock() }
            return applied[key(roundId, holeIndex, uid, installId)]
        }
        func recordApplied(_ roundId: String, _ holeIndex: Int, _ uid: String, _ installId: String, _ sequence: Int) {
            lock.lock(); defer { lock.unlock() }
            applied[key(roundId, holeIndex, uid, installId)] = sequence
        }
    }

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

    private func makeBatch(roundId: String = "r1", holeNumber: Int = 1, clubs: [String], sequence: Int = 1, installId: String = "install-A") -> WatchShotBatch {
        WatchShotBatch(roundId: roundId, entries: [WatchShotEntry(holeNumber: holeNumber, clubs: clubs, recordedAt: Date(), sequence: sequence, installId: installId)])
    }

    /// Простой захватываемый по ссылке контейнер для тестов, которым нужно
    /// смоделировать эволюцию "серверного" состояния между двумя вызовами
    /// applyBatch.
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
            },
            lastAppliedSequenceProvider: noOpLastApplied,
            sequenceRecorder: noOpSequenceRecorder
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
            shotRecorder: { _, _, _, clubs, _ in recordedClubs = clubs; return .synced },
            lastAppliedSequenceProvider: noOpLastApplied,
            sequenceRecorder: noOpSequenceRecorder
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
            shotRecorder: { _, _, _, _, distances in recordedDistances = distances; return .synced },
            lastAppliedSequenceProvider: noOpLastApplied,
            sequenceRecorder: noOpSequenceRecorder
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
            receiptSender: { sentReceipt = $0 },
            lastAppliedSequenceProvider: noOpLastApplied,
            sequenceRecorder: noOpSequenceRecorder
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
            receiptSender: { sentReceipt = $0 },
            lastAppliedSequenceProvider: noOpLastApplied,
            sequenceRecorder: noOpSequenceRecorder
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
            receiptSender: { sentReceipt = $0 },
            lastAppliedSequenceProvider: noOpLastApplied,
            sequenceRecorder: noOpSequenceRecorder
        )
        let batch = WatchShotBatch(roundId: "r1", entries: [
            WatchShotEntry(holeNumber: 1, clubs: ["Driver"], recordedAt: Date(), sequence: 1, installId: "install-A"),
            WatchShotEntry(holeNumber: 2, clubs: ["Putter"], recordedAt: Date(), sequence: 1, installId: "install-A"),
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
            receiptSender: { sentReceipt = $0 },
            lastAppliedSequenceProvider: noOpLastApplied,
            sequenceRecorder: noOpSequenceRecorder
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
            shotRecorder: { _, _, _, _, _ in recorderCalled = true; return .synced },
            lastAppliedSequenceProvider: noOpLastApplied,
            sequenceRecorder: noOpSequenceRecorder
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
            shotRecorder: { _, _, _, _, _ in recorderCalled = true; return .synced },
            lastAppliedSequenceProvider: noOpLastApplied,
            sequenceRecorder: noOpSequenceRecorder
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
            shotRecorder: { _, holeIndex, _, _, _ in recordedHoleIndices.append(holeIndex); return .synced },
            lastAppliedSequenceProvider: noOpLastApplied,
            sequenceRecorder: noOpSequenceRecorder
        )
        let batch = WatchShotBatch(roundId: "r1", entries: [
            WatchShotEntry(holeNumber: 1, clubs: ["Driver"], recordedAt: Date(), sequence: 1, installId: "install-A"),
            WatchShotEntry(holeNumber: 99, clubs: ["Putter"], recordedAt: Date(), sequence: 1, installId: "install-A"),
        ])
        await bridge.applyBatch(batch)
        XCTAssertEqual(recordedHoleIndices, [0], "лунка за пределами раунда пропущена, а не роняет весь батч")
    }

    // MARK: - Fix 5 (живое ревью): идемпотентность по sequence, НЕ по
    // содержимому клюшек. Прежняя suffix-эвристика путала "этот батч уже
    // применён" с "игрок ударил той же клюшкой ещё раз" (второй патт на
    // том же грине — рутинный случай в гольфе) и молча теряла удар.

    func testSameClubHitTwiceWithDifferentSequenceIsAppliedTwice() async {
        // Именно сценарий, который ломала suffix-эвристика: два путта
        // ПОДРЯД одной и той же клюшкой на одной лунке — РАЗНЫЕ sequence
        // (реально новый удар каждый раз), должны оба попасть на сервер.
        let ledger = FakeSequenceLedger()
        let store = FakeServerState()
        let bridge = WatchBridge(
            currentUserIdProvider: { "user-1" },
            roundProvider: { _ in self.makeRound(clubsForUser: store.clubs.isEmpty ? [:] : [1: store.clubs]) },
            pendingShotProvider: { _, _, _ in nil },
            shotRecorder: { _, _, _, clubs, _ in store.clubs = clubs; return .synced },
            lastAppliedSequenceProvider: { ledger.lastApplied($0, $1, $2, $3) },
            sequenceRecorder: { ledger.recordApplied($0, $1, $2, $3, $4) }
        )

        await bridge.applyBatch(makeBatch(holeNumber: 1, clubs: ["Putter"], sequence: 1))
        XCTAssertEqual(store.clubs, ["Putter"])

        await bridge.applyBatch(makeBatch(holeNumber: 1, clubs: ["Putter"], sequence: 2))
        XCTAssertEqual(store.clubs, ["Putter", "Putter"], "второй патт той же клюшкой — реальный новый удар, не дубль")
    }

    func testSameSequenceDeliveredTwiceIsAppliedOnceButAcknowledgedTwice() async {
        let ledger = FakeSequenceLedger()
        let store = FakeServerState()
        var receiptCount = 0
        let bridge = WatchBridge(
            currentUserIdProvider: { "user-1" },
            roundProvider: { _ in self.makeRound(clubsForUser: store.clubs.isEmpty ? [:] : [1: store.clubs]) },
            pendingShotProvider: { _, _, _ in nil },
            shotRecorder: { _, _, _, clubs, _ in store.clubs = clubs; return .synced },
            receiptSender: { _ in receiptCount += 1 },
            lastAppliedSequenceProvider: { ledger.lastApplied($0, $1, $2, $3) },
            sequenceRecorder: { ledger.recordApplied($0, $1, $2, $3, $4) }
        )
        let batch = makeBatch(holeNumber: 1, clubs: ["Putter"], sequence: 1)

        await bridge.applyBatch(batch)
        XCTAssertEqual(store.clubs, ["Putter"])

        // Повторная доставка ТОГО ЖЕ sequence (throttle-ретрай на часах,
        // гонка с запоздавшей оригинальной отправкой — см.
        // WatchShotQueue.inFlightTimeout).
        await bridge.applyBatch(batch)
        XCTAssertEqual(store.clubs, ["Putter"], "применено только ОДИН раз — не дубль")
        XCTAssertEqual(receiptCount, 2, "но квитанция уходит на КАЖДУЮ доставку — иначе слот на часах зависнет")
    }

    func testOlderSequenceThanLastAppliedIsSkipped() async {
        let ledger = FakeSequenceLedger()
        var recorderCalled = false
        let bridge = WatchBridge(
            currentUserIdProvider: { "user-1" },
            roundProvider: { _ in self.makeRound() },
            pendingShotProvider: { _, _, _ in nil },
            shotRecorder: { _, _, _, _, _ in recorderCalled = true; return .synced },
            lastAppliedSequenceProvider: { ledger.lastApplied($0, $1, $2, $3) },
            sequenceRecorder: { ledger.recordApplied($0, $1, $2, $3, $4) }
        )
        await bridge.applyBatch(makeBatch(holeNumber: 1, clubs: ["Driver"], sequence: 5))
        recorderCalled = false

        await bridge.applyBatch(makeBatch(holeNumber: 1, clubs: ["Putter"], sequence: 3))
        XCTAssertFalse(recorderCalled, "sequence 3 <= последнего применённого (5) — не применяем")
    }

    // MARK: - Fix 8 (живое ревью): переустановка часов — новый installId —
    // не коллизирует с sequence прежней установки.

    func testSameSequenceButDifferentInstallIdIsApplied() async {
        let ledger = FakeSequenceLedger()
        var recordedClubs: [String]?
        let bridge = WatchBridge(
            currentUserIdProvider: { "user-1" },
            roundProvider: { _ in self.makeRound() },
            pendingShotProvider: { _, _, _ in nil },
            shotRecorder: { _, _, _, clubs, _ in recordedClubs = clubs; return .synced },
            lastAppliedSequenceProvider: { ledger.lastApplied($0, $1, $2, $3) },
            sequenceRecorder: { ledger.recordApplied($0, $1, $2, $3, $4) }
        )
        // Прежняя установка часов уже применила sequence: 5.
        await bridge.applyBatch(makeBatch(holeNumber: 1, clubs: ["Driver"], sequence: 5, installId: "install-OLD"))
        recordedClubs = nil

        // Часы переустановлены — новый installId, счётчик sequence на них
        // тоже обнулился: первый настоящий удар новой установки несёт
        // sequence: 1. Без Fix 8 это выглядело бы как "уже применённый"
        // (1 <= 5 из прежней установки) и молча пропало бы.
        await bridge.applyBatch(makeBatch(holeNumber: 1, clubs: ["Putter"], sequence: 1, installId: "install-NEW"))

        XCTAssertNotNil(recordedClubs, "новая установка должна применяться независимо от sequence прежней")
    }

    // MARK: - Fix 4: идемпотентность/рост при переиспользовании round-провайдера

    func testRepeatingSameBatchIsIdempotentAgainstUpdatedServerState() async {
        let ledger = FakeSequenceLedger()
        let store = FakeServerState()
        let bridge = WatchBridge(
            currentUserIdProvider: { "user-1" },
            roundProvider: { _ in self.makeRound(clubsForUser: store.clubs.isEmpty ? [:] : [1: store.clubs]) },
            pendingShotProvider: { _, _, _ in nil },
            shotRecorder: { _, _, _, clubs, _ in store.clubs = clubs; return .synced },
            lastAppliedSequenceProvider: { ledger.lastApplied($0, $1, $2, $3) },
            sequenceRecorder: { ledger.recordApplied($0, $1, $2, $3, $4) }
        )
        let batch = makeBatch(holeNumber: 1, clubs: ["Driver"], sequence: 1)

        await bridge.applyBatch(batch)
        XCTAssertEqual(store.clubs, ["Driver"])

        await bridge.applyBatch(batch)
        XCTAssertEqual(store.clubs, ["Driver"], "повтор одного и того же батча (тот же sequence) не должен плодить дубликат")
    }

    func testGrowingTailAfterPreviousBatchAppendsOnlyNewPortion() async {
        let ledger = FakeSequenceLedger()
        let store = FakeServerState()
        let bridge = WatchBridge(
            currentUserIdProvider: { "user-1" },
            roundProvider: { _ in self.makeRound(clubsForUser: store.clubs.isEmpty ? [:] : [1: store.clubs]) },
            pendingShotProvider: { _, _, _ in nil },
            shotRecorder: { _, _, _, clubs, _ in store.clubs = clubs; return .synced },
            lastAppliedSequenceProvider: { ledger.lastApplied($0, $1, $2, $3) },
            sequenceRecorder: { ledger.recordApplied($0, $1, $2, $3, $4) }
        )
        await bridge.applyBatch(makeBatch(holeNumber: 1, clubs: ["Driver"], sequence: 1))
        XCTAssertEqual(store.clubs, ["Driver"])

        await bridge.applyBatch(makeBatch(holeNumber: 1, clubs: ["7 Iron"], sequence: 2))
        XCTAssertEqual(store.clubs, ["Driver", "7 Iron"], "новый (не повторяющийся) хвост дописывается как обычно")
    }
}
