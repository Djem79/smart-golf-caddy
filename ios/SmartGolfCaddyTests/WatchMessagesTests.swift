// ios/SmartGolfCaddyTests/WatchMessagesTests.swift
// Кодирование контракта телефон ↔ часы. Без импорта WatchConnectivity —
// проверяем только payload round-trip (структуры Foundation-only).
import XCTest
@testable import SmartGolfCaddy

final class WatchMessagesTests: XCTestCase {

    // MARK: - WatchRoundSnapshot

    private func makeSnapshot() -> WatchRoundSnapshot {
        WatchRoundSnapshot(
            roundId: "round-1",
            courseName: "Krylatskoye",
            totalHoles: 18,
            holes: [
                WatchHole(number: 1, par: 4, distanceMeters: 380, myShots: 0),
                WatchHole(number: 2, par: 3, distanceMeters: 160, myShots: 2),
            ],
            clubs: ["driver", "7-iron", "putter"],
            greens: [1: GreenMark(lat: 55.700, lng: 37.400), 2: GreenMark(lat: 55.701, lng: 37.401)],
            activeHoleNumber: 2,
            unitsYards: false,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testSnapshotRoundTrip() throws {
        let original = makeSnapshot()
        let restored = try XCTUnwrap(WatchRoundSnapshot(payload: original.payload))
        XCTAssertEqual(restored, original)
    }

    func testSnapshotPayloadHasVersion1() {
        let payload = makeSnapshot().payload
        XCTAssertEqual(payload["v"] as? Int, 1)
    }

    func testSnapshotPreservesHoleAndClubOrder() throws {
        let original = makeSnapshot()
        let restored = try XCTUnwrap(WatchRoundSnapshot(payload: original.payload))
        XCTAssertEqual(restored.holes.map(\.number), [1, 2])
        XCTAssertEqual(restored.clubs, ["driver", "7-iron", "putter"])
    }

    func testSnapshotPreservesGreens() throws {
        let original = makeSnapshot()
        let restored = try XCTUnwrap(WatchRoundSnapshot(payload: original.payload))
        XCTAssertEqual(restored.greens, original.greens)
    }

    func testSnapshotRejectsWrongVersion() {
        var payload = makeSnapshot().payload
        payload["v"] = 2
        XCTAssertNil(WatchRoundSnapshot(payload: payload))
    }

    func testSnapshotRejectsMissingRequiredField() {
        var payload = makeSnapshot().payload
        payload.removeValue(forKey: "roundId")
        XCTAssertNil(WatchRoundSnapshot(payload: payload))
    }

    func testSnapshotRejectsGarbage() {
        XCTAssertNil(WatchRoundSnapshot(payload: ["v": 1, "roundId": 42]))
        XCTAssertNil(WatchRoundSnapshot(payload: [:]))
        XCTAssertNil(WatchRoundSnapshot(payload: ["garbage": "value"]))
    }

    func testSnapshotToleratesMissingGreens() throws {
        // greens может отсутствовать для лунок без меток — не должно валить init.
        var payload = makeSnapshot().payload
        payload["greens"] = [String: [String: Double]]()
        let restored = try XCTUnwrap(WatchRoundSnapshot(payload: payload))
        XCTAssertTrue(restored.greens.isEmpty)
    }

    // MARK: - WatchShotBatch

    private func makeBatch() -> WatchShotBatch {
        WatchShotBatch(
            roundId: "round-1",
            entries: [
                WatchShotEntry(holeNumber: 1, clubs: ["driver", "7-iron"], recordedAt: Date(timeIntervalSince1970: 1_700_000_100)),
                WatchShotEntry(holeNumber: 2, clubs: ["putter"], recordedAt: Date(timeIntervalSince1970: 1_700_000_200)),
            ]
        )
    }

    func testBatchRoundTrip() throws {
        let original = makeBatch()
        let restored = try XCTUnwrap(WatchShotBatch(payload: original.payload))
        XCTAssertEqual(restored, original)
    }

    func testBatchPayloadHasVersion1() {
        let payload = makeBatch().payload
        XCTAssertEqual(payload["v"] as? Int, 1)
    }

    func testBatchPreservesEntryAndClubOrder() throws {
        let original = makeBatch()
        let restored = try XCTUnwrap(WatchShotBatch(payload: original.payload))
        XCTAssertEqual(restored.entries.map(\.holeNumber), [1, 2])
        XCTAssertEqual(restored.entries[0].clubs, ["driver", "7-iron"])
    }

    func testBatchRejectsWrongVersion() {
        var payload = makeBatch().payload
        payload["v"] = 2
        XCTAssertNil(WatchShotBatch(payload: payload))
    }

    func testBatchRejectsMissingRequiredField() {
        var payload = makeBatch().payload
        payload.removeValue(forKey: "entries")
        XCTAssertNil(WatchShotBatch(payload: payload))
    }

    func testBatchRejectsGarbage() {
        XCTAssertNil(WatchShotBatch(payload: ["v": 1, "roundId": 1]))
        XCTAssertNil(WatchShotBatch(payload: [:]))
        XCTAssertNil(WatchShotBatch(payload: ["garbage": "value"]))
    }

    func testBatchTogglesEmptyEntries() throws {
        var payload = makeBatch().payload
        payload["entries"] = [[String: Any]]()
        let restored = try XCTUnwrap(WatchShotBatch(payload: payload))
        XCTAssertTrue(restored.entries.isEmpty)
    }
}
