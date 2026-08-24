// ios/SmartGolfCaddyTests/WatchBatchSequenceLedgerTests.swift
// Тесты WatchBatchSequenceLedger (Fix 5+8, живое ревью Task 4) — durable
// журнал "последний применённый sequence" на телефоне, ключуется по
// round:holeIndex:uid:installId.
import XCTest
@testable import SmartGolfCaddy

final class WatchBatchSequenceLedgerTests: XCTestCase {
    private var storeURL: URL!

    override func setUp() {
        super.setUp()
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchbatchsequence-test-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeURL)
        super.tearDown()
    }

    private func makeLedger() -> WatchBatchSequenceLedger {
        WatchBatchSequenceLedger(storeURL: storeURL)
    }

    func testLastAppliedNilForUnknownSlot() {
        let ledger = makeLedger()
        XCTAssertNil(ledger.lastApplied(roundId: "r", holeIndex: 0, uid: "u", installId: "install-A"))
    }

    func testRecordAppliedIsReadableImmediately() {
        let ledger = makeLedger()
        ledger.recordApplied(roundId: "r", holeIndex: 0, uid: "u", installId: "install-A", sequence: 3)
        XCTAssertEqual(ledger.lastApplied(roundId: "r", holeIndex: 0, uid: "u", installId: "install-A"), 3)
    }

    func testSurvivesRestart() {
        let ledger = makeLedger()
        ledger.recordApplied(roundId: "r", holeIndex: 2, uid: "u1", installId: "install-A", sequence: 7)

        // "Перезапуск" телефона — новый инстанс над тем же файлу.
        let reloaded = WatchBatchSequenceLedger(storeURL: storeURL)
        XCTAssertEqual(reloaded.lastApplied(roundId: "r", holeIndex: 2, uid: "u1", installId: "install-A"), 7)
    }

    func testDoesNotLowerAlreadyRecordedSequence() {
        let ledger = makeLedger()
        ledger.recordApplied(roundId: "r", holeIndex: 0, uid: "u", installId: "install-A", sequence: 5)
        ledger.recordApplied(roundId: "r", holeIndex: 0, uid: "u", installId: "install-A", sequence: 2)
        XCTAssertEqual(ledger.lastApplied(roundId: "r", holeIndex: 0, uid: "u", installId: "install-A"), 5, "младший sequence не должен откатить журнал назад")
    }

    func testDifferentSlotsDoNotCollide() {
        let ledger = makeLedger()
        ledger.recordApplied(roundId: "r", holeIndex: 0, uid: "u1", installId: "install-A", sequence: 1)
        ledger.recordApplied(roundId: "r", holeIndex: 1, uid: "u1", installId: "install-A", sequence: 9)
        ledger.recordApplied(roundId: "r", holeIndex: 0, uid: "u2", installId: "install-A", sequence: 4)
        XCTAssertEqual(ledger.lastApplied(roundId: "r", holeIndex: 0, uid: "u1", installId: "install-A"), 1)
        XCTAssertEqual(ledger.lastApplied(roundId: "r", holeIndex: 1, uid: "u1", installId: "install-A"), 9)
        XCTAssertEqual(ledger.lastApplied(roundId: "r", holeIndex: 0, uid: "u2", installId: "install-A"), 4)
    }

    // MARK: - Fix 8 (живое ревью Task 4): переустановка приложения часов
    // получает СОБСТВЕННОЕ пространство sequence, не коллизирует с прежним.

    func testDifferentInstallIdsDoNotCollideOnSameSequence() {
        let ledger = makeLedger()
        ledger.recordApplied(roundId: "r", holeIndex: 0, uid: "u", installId: "install-OLD", sequence: 5)

        // Приложение переустановлено — новый installId, счётчик sequence
        // на часах тоже обнулился, поэтому новый настоящий удар придёт с
        // sequence: 1. Без учёта installId это выглядело бы как "уже
        // применённый" (1 <= 5) и телефон молча пропустил бы запись.
        XCTAssertNil(
            ledger.lastApplied(roundId: "r", holeIndex: 0, uid: "u", installId: "install-NEW"),
            "новая установка не видит журнал прежней — своё пространство sequence по построению"
        )
    }
}
