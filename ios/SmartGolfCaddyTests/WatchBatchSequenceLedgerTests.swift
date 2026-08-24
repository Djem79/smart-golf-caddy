// ios/SmartGolfCaddyTests/WatchBatchSequenceLedgerTests.swift
// Тесты WatchBatchSequenceLedger (Fix 5, живое ревью Task 4) — durable
// журнал "последний применённый sequence" на телефоне.
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
        XCTAssertNil(ledger.lastApplied(roundId: "r", holeIndex: 0, uid: "u"))
    }

    func testRecordAppliedIsReadableImmediately() {
        let ledger = makeLedger()
        ledger.recordApplied(roundId: "r", holeIndex: 0, uid: "u", sequence: 3)
        XCTAssertEqual(ledger.lastApplied(roundId: "r", holeIndex: 0, uid: "u"), 3)
    }

    func testSurvivesRestart() {
        let ledger = makeLedger()
        ledger.recordApplied(roundId: "r", holeIndex: 2, uid: "u1", sequence: 7)

        // "Перезапуск" телефона — новый инстанс над тем же файлу.
        let reloaded = WatchBatchSequenceLedger(storeURL: storeURL)
        XCTAssertEqual(reloaded.lastApplied(roundId: "r", holeIndex: 2, uid: "u1"), 7)
    }

    func testDoesNotLowerAlreadyRecordedSequence() {
        let ledger = makeLedger()
        ledger.recordApplied(roundId: "r", holeIndex: 0, uid: "u", sequence: 5)
        ledger.recordApplied(roundId: "r", holeIndex: 0, uid: "u", sequence: 2)
        XCTAssertEqual(ledger.lastApplied(roundId: "r", holeIndex: 0, uid: "u"), 5, "младший sequence не должен откатить журнал назад")
    }

    func testDifferentSlotsDoNotCollide() {
        let ledger = makeLedger()
        ledger.recordApplied(roundId: "r", holeIndex: 0, uid: "u1", sequence: 1)
        ledger.recordApplied(roundId: "r", holeIndex: 1, uid: "u1", sequence: 9)
        ledger.recordApplied(roundId: "r", holeIndex: 0, uid: "u2", sequence: 4)
        XCTAssertEqual(ledger.lastApplied(roundId: "r", holeIndex: 0, uid: "u1"), 1)
        XCTAssertEqual(ledger.lastApplied(roundId: "r", holeIndex: 1, uid: "u1"), 9)
        XCTAssertEqual(ledger.lastApplied(roundId: "r", holeIndex: 0, uid: "u2"), 4)
    }
}
