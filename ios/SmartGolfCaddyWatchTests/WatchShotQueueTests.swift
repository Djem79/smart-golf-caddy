// ios/SmartGolfCaddyWatchTests/WatchShotQueueTests.swift
// Тесты WatchShotQueue (Task 4, Phase 3c) — durable-очередь ударов на
// часах: переживает "перезапуск" (новый инстанс над тем же файлом),
// last-write-wins на слот "roundId:holeNumber" (повтор не плодит записи),
// запись снимается ТОЛЬКО по квитанции (markConfirmed), flush НЕ удаляет.
import XCTest
@testable import SmartGolfCaddyWatch

final class WatchShotQueueTests: XCTestCase {
    private var storeURL: URL!
    private var sequenceStoreURL: URL!
    private var installIdStoreURL: URL!

    override func setUp() {
        super.setUp()
        let id = UUID().uuidString
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchshotqueue-test-\(id).json")
        sequenceStoreURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchshotqueue-sequence-test-\(id).json")
        installIdStoreURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchshotqueue-installid-test-\(id).txt")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default.removeItem(at: sequenceStoreURL)
        try? FileManager.default.removeItem(at: installIdStoreURL)
        super.tearDown()
    }

    private func makeQueue() -> WatchShotQueue {
        WatchShotQueue(storeURL: storeURL, sequenceStoreURL: sequenceStoreURL, installIdStoreURL: installIdStoreURL)
    }

    // MARK: - enqueue / pending

    func testEnqueueMakesEntryVisibleInPending() {
        let queue = makeQueue()
        queue.enqueue(roundId: "r", holeNumber: 4, clubs: ["Driver"])
        XCTAssertEqual(queue.pending.count, 1)
        XCTAssertEqual(queue.pending.first?.roundId, "r")
        XCTAssertEqual(queue.pending.first?.holeNumber, 4)
        XCTAssertEqual(queue.pending.first?.clubs, ["Driver"])
    }

    func testEnqueueWithEmptyClubsRemovesSlot() {
        let queue = makeQueue()
        queue.enqueue(roundId: "r", holeNumber: 4, clubs: ["Driver"])
        queue.enqueue(roundId: "r", holeNumber: 4, clubs: [])
        XCTAssertTrue(queue.pending.isEmpty, "пустой хвост — нечего хранить и слать")
    }

    // MARK: - переживает перезапуск (новый инстанс над тем же файлом)

    func testSurvivesRestart() {
        let queue = makeQueue()
        queue.enqueue(roundId: "r", holeNumber: 2, clubs: ["7 Iron", "Putter"])

        let reloaded = makeQueue()
        XCTAssertEqual(reloaded.pending.count, 1)
        XCTAssertEqual(reloaded.pending.first?.clubs, ["7 Iron", "Putter"])
    }

    // MARK: - повтор не плодит дубликаты (last-write-wins на слот)

    func testRepeatedEnqueueSameSlotDoesNotDuplicate() {
        let queue = makeQueue()
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver"])
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver", "PW"])
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver", "PW", "Putter"])
        XCTAssertEqual(queue.pending.count, 1, "один слот — одна запись, а не история")
        XCTAssertEqual(queue.pending.first?.clubs, ["Driver", "PW", "Putter"], "последняя запись выигрывает")
    }

    func testDifferentHolesDoNotCollide() {
        let queue = makeQueue()
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver"])
        queue.enqueue(roundId: "r", holeNumber: 2, clubs: ["Putter"])
        XCTAssertEqual(queue.pending.count, 2)
    }

    func testDifferentRoundsDoNotCollideOnSameHoleNumber() {
        let queue = makeQueue()
        queue.enqueue(roundId: "round-A", holeNumber: 1, clubs: ["Driver"])
        queue.enqueue(roundId: "round-B", holeNumber: 1, clubs: ["Putter"])
        XCTAssertEqual(queue.pending.count, 2)
    }

    // MARK: - markConfirmed по квитанции чистит очередь

    func testMarkConfirmedFullyClearsSlot() {
        let queue = makeQueue()
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver"])
        queue.markConfirmed(roundId: "r", holeNumber: 1, acceptedCount: 1)
        XCTAssertTrue(queue.pending.isEmpty)
    }

    func testMarkConfirmedOverAcceptStillClearsSlot() {
        // Квитанция сообщает больше, чем сейчас в очереди (например, дубликат
        // старой квитанции пришёл после того как хвост уже подрос иначе) —
        // безопасно снимаем целиком, а не уходим в отрицательный остаток.
        let queue = makeQueue()
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver"])
        queue.markConfirmed(roundId: "r", holeNumber: 1, acceptedCount: 5)
        XCTAssertTrue(queue.pending.isEmpty)
    }

    func testMarkConfirmedPartialTrimsConfirmedPrefix() {
        // Пользователь успел добавить удар на часах, пока квитанция была в
        // пути: квитанция подтверждает только префикс — остаток (новый
        // удар) должен остаться в очереди для следующей отправки.
        let queue = makeQueue()
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver", "7 Iron"])
        queue.markConfirmed(roundId: "r", holeNumber: 1, acceptedCount: 1)
        XCTAssertEqual(queue.pending.count, 1)
        XCTAssertEqual(queue.pending.first?.clubs, ["7 Iron"], "подтверждённый префикс срезан, новый хвост остался")
    }

    func testMarkConfirmedZeroIsNoOp() {
        let queue = makeQueue()
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver"])
        queue.markConfirmed(roundId: "r", holeNumber: 1, acceptedCount: 0)
        XCTAssertEqual(queue.pending.first?.clubs, ["Driver"])
    }

    func testMarkConfirmedOnMissingSlotIsNoOp() {
        let queue = makeQueue()
        queue.markConfirmed(roundId: "r", holeNumber: 1, acceptedCount: 1)
        XCTAssertTrue(queue.pending.isEmpty)
    }

    func testMarkConfirmedOnlyAffectsMatchingSlot() {
        let queue = makeQueue()
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver"])
        queue.enqueue(roundId: "r", holeNumber: 2, clubs: ["Putter"])
        queue.markConfirmed(roundId: "r", holeNumber: 1, acceptedCount: 1)
        XCTAssertEqual(queue.pending.count, 1)
        XCTAssertEqual(queue.pending.first?.holeNumber, 2)
    }

    // MARK: - flush отправляет, но НЕ удаляет (снимает только markConfirmed)

    func testFlushSendsAllPendingEntriesGroupedByRound() {
        let queue = makeQueue()
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver"])
        queue.enqueue(roundId: "r", holeNumber: 2, clubs: ["Putter"])

        var sentBatches: [WatchShotBatch] = []
        queue.flush { batch in sentBatches.append(batch) }

        XCTAssertEqual(sentBatches.count, 1, "один раунд — один батч")
        XCTAssertEqual(sentBatches.first?.roundId, "r")
        XCTAssertEqual(Set(sentBatches.first?.entries.map(\.holeNumber) ?? []), [1, 2])
    }

    func testFlushDoesNotRemovePendingEntries() {
        let queue = makeQueue()
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver"])
        queue.flush { _ in }
        XCTAssertEqual(queue.pending.count, 1, "снять запись может только квитанция, не сам факт отправки")
    }

    func testFlushOnEmptyQueueDoesNotCallSend() {
        let queue = makeQueue()
        var called = false
        queue.flush { _ in called = true }
        XCTAssertFalse(called)
    }

    func testFlushEntryCarriesExactEnqueuedClubs() {
        let queue = makeQueue()
        queue.enqueue(roundId: "r", holeNumber: 4, clubs: ["Driver", "3 Wood"])

        var received: WatchShotEntry?
        queue.flush { batch in received = batch.entries.first }

        XCTAssertEqual(received?.holeNumber, 4)
        XCTAssertEqual(received?.clubs, ["Driver", "3 Wood"])
    }

    // MARK: - "В пути" throttle — ключевая защита от дублей на телефоне.
    //
    // recordShot на телефоне ДОПИСЫВАЕТ присланный хвост к уже известным
    // клюшкам (см. WatchBridge) — если один и тот же ещё-не-подтверждённый
    // хвост уйдёт ДВАЖДЫ до прихода квитанции, телефон дважды допишет одни
    // и те же клюшки. flush() обязан пропускать слот, для которого отправка
    // уже "в пути" (батч ушёл, квитанции ещё нет) — resend только после
    // markConfirmed ИЛИ по таймауту (на случай, если отправка молча не
    // удалась и квитанции не будет никогда).

    func testFlushDoesNotResendSlotStillInFlight() {
        let queue = makeQueue()
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver"])

        var sendCount = 0
        queue.flush { _ in sendCount += 1 }
        queue.flush { _ in sendCount += 1 }
        queue.flush { _ in sendCount += 1 }

        XCTAssertEqual(sendCount, 1, "тот же неподтверждённый батч не должен уходить повторно")
    }

    func testFlushResendsGrowthAfterMarkConfirmedClearsInFlight() {
        let queue = makeQueue()
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver"])

        var sentClubs: [[String]] = []
        queue.flush { batch in sentClubs.append(batch.entries.first?.clubs ?? []) }
        XCTAssertEqual(sentClubs, [["Driver"]])

        // Пользователь добавил ещё удар, пока квитанция была в пути.
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver", "PW"])
        queue.flush { batch in sentClubs.append(batch.entries.first?.clubs ?? []) }
        XCTAssertEqual(sentClubs.count, 1, "слот всё ещё в пути — второй flush ничего не шлёт")

        // Телефон подтвердил первый батч (1 клюшка).
        queue.markConfirmed(roundId: "r", holeNumber: 1, acceptedCount: 1)
        queue.flush { batch in sentClubs.append(batch.entries.first?.clubs ?? []) }

        XCTAssertEqual(sentClubs, [["Driver"], ["PW"]], "после квитанции уходит только новый остаток, БЕЗ повтора уже подтверждённого")
    }

    func testFlushDoesNotThrottleDifferentSlots() {
        let queue = makeQueue()
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver"])
        queue.flush { _ in }

        var secondSent: WatchShotBatch?
        queue.enqueue(roundId: "r", holeNumber: 2, clubs: ["Putter"])
        queue.flush { batch in secondSent = batch }

        XCTAssertEqual(secondSent?.entries.map(\.holeNumber), [2], "другая лунка не заблокирована throttle'ом первой")
    }

    // MARK: - markConfirmed(accepted: false) — Fix 3, живое ревью Task 4:
    // окончательный отказ сервера чистит слот и оповещает UI, а не висит
    // вечно в throttle-цикле.

    func testRejectedReceiptClearsSlotLikeAccepted() {
        let queue = makeQueue()
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver"])
        queue.markConfirmed(roundId: "r", holeNumber: 1, acceptedCount: 1, accepted: false)
        XCTAssertTrue(queue.pending.isEmpty, "ретраить окончательно отклонённый payload бессмысленно")
    }

    func testRejectedReceiptPostsSyncFailedNotification() {
        let queue = makeQueue()
        let exp = expectation(forNotification: .watchShotSyncFailed, object: nil) { notification in
            (notification.userInfo?["roundId"] as? String) == "r"
                && (notification.userInfo?["holeNumber"] as? Int) == 4
        }
        queue.markConfirmed(roundId: "r", holeNumber: 4, acceptedCount: 1, accepted: false)
        wait(for: [exp], timeout: 1)
    }

    func testAcceptedReceiptDoesNotPostSyncFailedNotification() {
        let queue = makeQueue()
        var failedFired = false
        let observer = NotificationCenter.default.addObserver(forName: .watchShotSyncFailed, object: nil, queue: nil) { _ in
            failedFired = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver"])
        queue.markConfirmed(roundId: "r", holeNumber: 1, acceptedCount: 1)
        XCTAssertFalse(failedFired)
    }

    // MARK: - sequence (Fix 5, живое ревью Task 4) — присваивается ОДИН
    // РАЗ на реальное изменение содержимого (enqueue), НЕ на каждую
    // отправку (flush) — переотправка того же объекта несёт тот же
    // sequence, что и раньше.

    func testFirstEnqueueGetsSequenceOne() {
        let queue = makeQueue()
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver"])
        XCTAssertEqual(queue.pending.first?.sequence, 1)
    }

    func testEachEnqueueWithNewContentGetsIncreasingSequence() {
        let queue = makeQueue()
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver"])
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver", "PW"])
        XCTAssertEqual(queue.pending.first?.sequence, 2)
    }

    func testFlushSendsTheStoredSequence() {
        let queue = makeQueue()
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver"])
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver", "PW"])  // sequence становится 2
        var sentSequence: Int?
        queue.flush { batch in sentSequence = batch.entries.first?.sequence }
        XCTAssertEqual(sentSequence, 2, "flush шлёт ТЕКУЩИЙ сохранённый sequence, не пересчитывает его заново")
    }

    func testSequenceKeepsIncrementingAcrossSlotClearAndReEnqueue() {
        // Критично для Fix 5: после markConfirmed (слот снят) следующий
        // enqueue НЕ должен начинать нумерацию заново — иначе новый
        // sequence мог бы совпасть с уже применённым на телефоне и
        // заставить его молча ПРОПУСТИТЬ реально новый удар (тот самый
        // сценарий "второй патт", который ловит живое ревью).
        let queue = makeQueue()
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Putter"])
        XCTAssertEqual(queue.pending.first?.sequence, 1)

        queue.markConfirmed(roundId: "r", holeNumber: 1, acceptedCount: 1)
        XCTAssertTrue(queue.pending.isEmpty)

        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Putter"])
        XCTAssertEqual(queue.pending.first?.sequence, 2, "нумерация продолжается, а не начинается заново с 1")
    }

    func testSequenceSurvivesRestart() {
        let queue = makeQueue()
        queue.enqueue(roundId: "r", holeNumber: 1, clubs: ["Driver"])
        queue.markConfirmed(roundId: "r", holeNumber: 1, acceptedCount: 1)

        let reloaded = WatchShotQueue(storeURL: storeURL, sequenceStoreURL: sequenceStoreURL, installIdStoreURL: installIdStoreURL)
        reloaded.enqueue(roundId: "r", holeNumber: 1, clubs: ["Putter"])
        XCTAssertEqual(reloaded.pending.first?.sequence, 2, "счётчик sequence пережил перезапуск (новый инстанс над тем же файлом)")
    }

    func testClearSequencesRemovesOnlyGivenRound() {
        let queue = makeQueue()
        queue.enqueue(roundId: "round-A", holeNumber: 1, clubs: ["Driver"])
        queue.markConfirmed(roundId: "round-A", holeNumber: 1, acceptedCount: 1)
        queue.enqueue(roundId: "round-B", holeNumber: 1, clubs: ["Driver"])
        queue.markConfirmed(roundId: "round-B", holeNumber: 1, acceptedCount: 1)

        queue.clearSequences(roundId: "round-A")

        queue.enqueue(roundId: "round-A", holeNumber: 1, clubs: ["Putter"])
        XCTAssertEqual(queue.pending.first?.sequence, 1, "счётчик round-A сброшен")

        queue.enqueue(roundId: "round-B", holeNumber: 1, clubs: ["Putter"])
        XCTAssertEqual(queue.pending.first { $0.roundId == "round-B" }?.sequence, 2, "round-B не задет")
    }

    // MARK: - installId (Fix 8/10, живое ревью Task 4) — durable-идентификатор
    // установки, генерируется один раз, переживает "перезапуск".

    func testInstallIdIsStable() {
        let queue = makeQueue()
        let first = queue.installId
        let second = queue.installId
        XCTAssertEqual(first, second, "повторное обращение не генерирует новый id")
        XCTAssertFalse(first.isEmpty)
    }

    func testInstallIdSurvivesRestart() {
        let queue = makeQueue()
        let original = queue.installId

        // "Перезапуск" — новый инстанс над тем же файлом (НЕ переустановка
        // приложения, которая стёрла бы контейнер данных целиком).
        let reloaded = WatchShotQueue(storeURL: storeURL, sequenceStoreURL: sequenceStoreURL, installIdStoreURL: installIdStoreURL)
        XCTAssertEqual(reloaded.installId, original, "два инстанса над одним файлом дают ОДИН И ТОТ ЖЕ id")
    }

    func testFreshInstallGetsANewInstallId() {
        // "Переустановка" — файл installId отсутствует (стёрт вместе с
        // остальным контейнером данных) — новый инстанс над НОВЫМ путём
        // должен сгенерировать НОВЫЙ id, отличный от прежнего.
        let queue = makeQueue()
        let original = queue.installId

        let freshInstallIdURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchshotqueue-installid-fresh-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: freshInstallIdURL) }
        let freshInstall = WatchShotQueue(storeURL: storeURL, sequenceStoreURL: sequenceStoreURL, installIdStoreURL: freshInstallIdURL)
        XCTAssertNotEqual(freshInstall.installId, original)
    }
}
