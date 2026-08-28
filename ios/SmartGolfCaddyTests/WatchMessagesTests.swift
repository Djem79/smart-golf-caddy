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
            units: .m,
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

    func testSnapshotToleratesEmptyGreensDict() throws {
        // Пустой словарь greens (лунки без меток) — не должно валить init.
        var payload = makeSnapshot().payload
        payload["greens"] = [String: [String: Double]]()
        let restored = try XCTUnwrap(WatchRoundSnapshot(payload: payload))
        XCTAssertTrue(restored.greens.isEmpty)
    }

    func testSnapshotDropsMalformedGreenMarkButKeepsRest() throws {
        // Одна битая метка грина (нечисловой lat) не должна валить весь
        // снимок — остальные метки декодируются как обычно.
        var payload = makeSnapshot().payload
        let greens = payload["greens"] as! [String: [String: Double]]
        var greensAny: [String: Any] = greens.mapValues { $0 as Any }
        greensAny["3"] = ["lat": "not-a-number", "lng": 37.4] as [String: Any]
        payload["greens"] = greensAny

        let restored = try XCTUnwrap(WatchRoundSnapshot(payload: payload))
        XCTAssertEqual(restored.greens.count, 2)
        XCTAssertNil(restored.greens[3])
        XCTAssertEqual(restored.greens[1], GreenMark(lat: 55.700, lng: 37.400))
    }

    func testSnapshotRoundTripsIntFieldsEncodedAsNSNumber() throws {
        // updateApplicationContext/transferUserInfo гоняют payload через
        // property-list/XPC: числа приходят как NSNumber, и его внутренний
        // числовой тип не обязан совпадать с исходным Int — round-trip в
        // одном процессе (Int остаётся Int) этот случай не ловит, поэтому
        // подставляем double-backed NSNumber туда, где ждём Int.
        var payload = makeSnapshot().payload
        payload["v"] = NSNumber(value: 1.0)
        payload["totalHoles"] = NSNumber(value: 18.0)
        payload["activeHoleNumber"] = NSNumber(value: 2.0)
        let holes = (payload["holes"] as! [[String: Any]]).map { hole -> [String: Any] in
            var h = hole
            h["number"] = NSNumber(value: Double(h["number"] as! Int))
            h["par"] = NSNumber(value: Double(h["par"] as! Int))
            h["distanceMeters"] = NSNumber(value: Double(h["distanceMeters"] as! Int))
            h["myShots"] = NSNumber(value: Double(h["myShots"] as! Int))
            return h
        }
        payload["holes"] = holes

        let restored = try XCTUnwrap(WatchRoundSnapshot(payload: payload))
        XCTAssertEqual(restored, makeSnapshot())
    }

    func testSnapshotRoundTripsDoubleFieldsEncodedAsIntBackedNSNumber() throws {
        // Обратный случай: updatedAt/lat/lng ждём как Double, а через XPC
        // может прийти int-backed NSNumber (например, целая секунда).
        var payload = makeSnapshot().payload
        payload["updatedAt"] = NSNumber(value: Int(1_700_000_000))
        let restored = try XCTUnwrap(WatchRoundSnapshot(payload: payload))
        XCTAssertEqual(restored.updatedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    // MARK: - WatchShotBatch

    private func makeBatch() -> WatchShotBatch {
        WatchShotBatch(
            roundId: "round-1",
            entries: [
                WatchShotEntry(holeNumber: 1, clubs: ["driver", "7-iron"], recordedAt: Date(timeIntervalSince1970: 1_700_000_100), sequence: 1, installId: "install-A"),
                WatchShotEntry(holeNumber: 2, clubs: ["putter"], recordedAt: Date(timeIntervalSince1970: 1_700_000_200), sequence: 3, installId: "install-A"),
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

    func testBatchPreservesSequence() throws {
        let original = makeBatch()
        let restored = try XCTUnwrap(WatchShotBatch(payload: original.payload))
        XCTAssertEqual(restored.entries.map(\.sequence), [1, 3])
    }

    func testBatchRejectsMissingSequenceField() {
        var payload = makeBatch().payload
        var entries = payload["entries"] as! [[String: Any]]
        entries[0].removeValue(forKey: "sequence")
        payload["entries"] = entries
        // Одна запись без sequence — весь батч невалиден (тот же строгий
        // инвариант entries.count == rawEntries.count, что и у остальных
        // обязательных полей контракта).
        XCTAssertNil(WatchShotBatch(payload: payload))
    }

    func testBatchPreservesInstallId() throws {
        let original = makeBatch()
        let restored = try XCTUnwrap(WatchShotBatch(payload: original.payload))
        XCTAssertEqual(restored.entries.map(\.installId), ["install-A", "install-A"])
    }

    func testBatchRejectsMissingInstallIdField() {
        var payload = makeBatch().payload
        var entries = payload["entries"] as! [[String: Any]]
        entries[0].removeValue(forKey: "installId")
        payload["entries"] = entries
        XCTAssertNil(WatchShotBatch(payload: payload))
    }

    func testBatchRejectsEmptyInstallId() {
        var payload = makeBatch().payload
        var entries = payload["entries"] as! [[String: Any]]
        entries[0]["installId"] = ""
        payload["entries"] = entries
        XCTAssertNil(WatchShotBatch(payload: payload))
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

    func testBatchAcceptsEmptyEntries() throws {
        var payload = makeBatch().payload
        payload["entries"] = [[String: Any]]()
        let restored = try XCTUnwrap(WatchShotBatch(payload: payload))
        XCTAssertTrue(restored.entries.isEmpty)
    }

    func testBatchRoundTripsFieldsEncodedAsNSNumber() throws {
        var payload = makeBatch().payload
        payload["v"] = NSNumber(value: 1.0)
        let entries = (payload["entries"] as! [[String: Any]]).map { entry -> [String: Any] in
            var e = entry
            e["holeNumber"] = NSNumber(value: Double(e["holeNumber"] as! Int))
            e["recordedAt"] = NSNumber(value: Int((e["recordedAt"] as! TimeInterval)))
            e["sequence"] = NSNumber(value: Double(e["sequence"] as! Int))
            return e
        }
        payload["entries"] = entries

        let restored = try XCTUnwrap(WatchShotBatch(payload: payload))
        XCTAssertEqual(restored.entries.map(\.holeNumber), [1, 2])
        XCTAssertEqual(restored.entries.map(\.recordedAt), makeBatch().entries.map(\.recordedAt))
        XCTAssertEqual(restored.entries.map(\.sequence), makeBatch().entries.map(\.sequence))
        XCTAssertEqual(restored.entries.map(\.installId), makeBatch().entries.map(\.installId))
    }

    // MARK: - WatchShotReceipt (телефон → часы, квитанция о приёме батча)

    private func makeReceipt() -> WatchShotReceipt {
        WatchShotReceipt(
            roundId: "round-1",
            entries: [
                WatchShotReceiptEntry(holeNumber: 1, acceptedCount: 2, accepted: true),
                WatchShotReceiptEntry(holeNumber: 2, acceptedCount: 1, accepted: false),
            ]
        )
    }

    func testReceiptRoundTrip() throws {
        let original = makeReceipt()
        let restored = try XCTUnwrap(WatchShotReceipt(payload: original.payload))
        XCTAssertEqual(restored, original)
    }

    func testReceiptPayloadHasVersion1() {
        let payload = makeReceipt().payload
        XCTAssertEqual(payload["v"] as? Int, 1)
    }

    func testReceiptPreservesEntryOrder() throws {
        let original = makeReceipt()
        let restored = try XCTUnwrap(WatchShotReceipt(payload: original.payload))
        XCTAssertEqual(restored.entries.map(\.holeNumber), [1, 2])
        XCTAssertEqual(restored.entries.map(\.acceptedCount), [2, 1])
    }

    func testReceiptPreservesAcceptedFlag() throws {
        let original = makeReceipt()
        let restored = try XCTUnwrap(WatchShotReceipt(payload: original.payload))
        XCTAssertEqual(restored.entries.map(\.accepted), [true, false])
    }

    func testReceiptRejectsMissingAcceptedField() {
        var payload = makeReceipt().payload
        var entries = payload["entries"] as! [[String: Any]]
        entries[0].removeValue(forKey: "accepted")
        payload["entries"] = entries
        // Одна запись без accepted — весь батч квитанций невалиден (тот же
        // строгий инвариант entries.count == rawEntries.count).
        XCTAssertNil(WatchShotReceipt(payload: payload))
    }

    func testReceiptRoundTripsAcceptedEncodedAsNSNumber() throws {
        // Bool через XPC/property-list иногда приходит NSNumber(bool:) —
        // та же гигиена, что у Int/Double полей контракта.
        var payload = makeReceipt().payload
        let entries = (payload["entries"] as! [[String: Any]]).map { entry -> [String: Any] in
            var e = entry
            e["accepted"] = NSNumber(value: e["accepted"] as! Bool)
            return e
        }
        payload["entries"] = entries
        let restored = try XCTUnwrap(WatchShotReceipt(payload: payload))
        XCTAssertEqual(restored, makeReceipt())
    }

    func testReceiptRejectsWrongVersion() {
        var payload = makeReceipt().payload
        payload["v"] = 2
        XCTAssertNil(WatchShotReceipt(payload: payload))
    }

    func testReceiptRejectsMissingRequiredField() {
        var payload = makeReceipt().payload
        payload.removeValue(forKey: "entries")
        XCTAssertNil(WatchShotReceipt(payload: payload))
    }

    func testReceiptRejectsGarbage() {
        XCTAssertNil(WatchShotReceipt(payload: ["v": 1, "roundId": 1]))
        XCTAssertNil(WatchShotReceipt(payload: [:]))
        XCTAssertNil(WatchShotReceipt(payload: ["garbage": "value"]))
    }

    func testReceiptAcceptsEmptyEntries() throws {
        var payload = makeReceipt().payload
        payload["entries"] = [[String: Any]]()
        let restored = try XCTUnwrap(WatchShotReceipt(payload: payload))
        XCTAssertTrue(restored.entries.isEmpty)
    }

    func testReceiptRoundTripsFieldsEncodedAsNSNumber() throws {
        // Та же XPC-гигиена, что и у WatchShotBatch — числа могут прийти как
        // NSNumber с иным внутренним типом.
        var payload = makeReceipt().payload
        payload["v"] = NSNumber(value: 1.0)
        let entries = (payload["entries"] as! [[String: Any]]).map { entry -> [String: Any] in
            var e = entry
            e["holeNumber"] = NSNumber(value: Double(e["holeNumber"] as! Int))
            e["acceptedCount"] = NSNumber(value: Double(e["acceptedCount"] as! Int))
            return e
        }
        payload["entries"] = entries

        let restored = try XCTUnwrap(WatchShotReceipt(payload: payload))
        XCTAssertEqual(restored, makeReceipt())
    }

    func testReceiptDropsMalformedEntryButKeepsRest() throws {
        var payload = makeReceipt().payload
        var entries = payload["entries"] as! [[String: Any]]
        entries.append(["holeNumber": "not-a-number", "acceptedCount": 1])
        payload["entries"] = entries
        // Целиком невалидная запись внутри массива — как и в WatchShotBatch,
        // весь массив компактится через compactMap с проверкой count ==
        // rawCount, поэтому здесь ожидаем провал ИМЕННО из-за строгости
        // инварианта "entries.count == rawEntries.count" (см. WatchShotBatch).
        XCTAssertNil(WatchShotReceipt(payload: payload))
    }
}
