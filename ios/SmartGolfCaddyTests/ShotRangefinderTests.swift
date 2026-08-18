import XCTest
@testable import SmartGolfCaddy

final class ShotRangefinderTests: XCTestCase {
    private var storeURL: URL!

    override func setUp() {
        super.setUp()
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rangefinder-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeURL)
        super.tearDown()
    }

    private func makeRangefinder(fix: @escaping () -> GeoFix?) -> ShotRangefinder {
        ShotRangefinder(storeURL: storeURL, fixProvider: fix)
    }

    func testAccuracyGate() {
        XCTAssertTrue(ShotRangefinder.isUsable(GeoFix(lat: 1, lng: 1, accuracy: 8, timestamp: Date())))
        XCTAssertFalse(ShotRangefinder.isUsable(GeoFix(lat: 1, lng: 1, accuracy: 60, timestamp: Date())))
        XCTAssertFalse(ShotRangefinder.isUsable(GeoFix(lat: 1, lng: 1, accuracy: -1, timestamp: Date())))
        XCTAssertFalse(ShotRangefinder.isUsable(nil))
    }

    func testStaleFixIsNotUsable() {
        // Фикс 5 минут назад (экран лежал заблокированным) — трекинг стоял,
        // lastFix замер; isUsable должен отсечь его по возрасту.
        let stale = GeoFix(lat: 1, lng: 1, accuracy: 5, timestamp: Date().addingTimeInterval(-300))
        XCTAssertFalse(ShotRangefinder.isUsable(stale))
        let fresh = GeoFix(lat: 1, lng: 1, accuracy: 5, timestamp: Date())
        XCTAssertTrue(ShotRangefinder.isUsable(fresh))
    }

    func testSanitizeRange() {
        XCTAssertEqual(ShotRangefinder.sanitize(214.6), 215)
        XCTAssertEqual(ShotRangefinder.sanitize(1.2), 0)     // ближе 3 м — шум
        XCTAssertEqual(ShotRangefinder.sanitize(900), 0)     // дальше 600 м — выброс
    }

    func testMeasureBetweenTwoFixes() {
        // ~111 м на север: 0.001° широты
        var current = GeoFix(lat: 55.700000, lng: 37.400000, accuracy: 5, timestamp: Date())
        let rangefinder = makeRangefinder(fix: { current })
        rangefinder.markShot(roundId: "r", holeIndex: 0, targetUid: "u", shotIndex: 0)
        current = GeoFix(lat: 55.701000, lng: 37.400000, accuracy: 5, timestamp: Date())
        let result = rangefinder.measure(roundId: "r", holeIndex: 0, targetUid: "u")
        XCTAssertEqual(result?.previousIndex, 0)
        XCTAssertEqual(Double(result?.meters ?? 0), 111, accuracy: 3)
    }

    func testMeasureWithoutMarkReturnsNil() {
        let rangefinder = makeRangefinder(fix: { GeoFix(lat: 1, lng: 1, accuracy: 5, timestamp: Date()) })
        XCTAssertNil(rangefinder.measure(roundId: "r", holeIndex: 0, targetUid: "u"))
    }

    func testMeasureWithBadAccuracyReturnsNil() {
        var current = GeoFix(lat: 55.7, lng: 37.4, accuracy: 5, timestamp: Date())
        let rangefinder = makeRangefinder(fix: { current })
        rangefinder.markShot(roundId: "r", holeIndex: 0, targetUid: "u", shotIndex: 0)
        current = GeoFix(lat: 55.701, lng: 37.4, accuracy: 80, timestamp: Date())
        XCTAssertNil(rangefinder.measure(roundId: "r", holeIndex: 0, targetUid: "u"))
    }

    func testMarksAreSlotScopedAndSurviveReload() {
        let rangefinder = makeRangefinder(fix: { GeoFix(lat: 55.7, lng: 37.4, accuracy: 5, timestamp: Date()) })
        rangefinder.markShot(roundId: "r", holeIndex: 0, targetUid: "u", shotIndex: 2)
        // Другой слот — своя точка
        XCTAssertNil(rangefinder.measure(roundId: "r", holeIndex: 1, targetUid: "u"))
        // «Перезапуск» — точка на месте
        let reloaded = makeRangefinder(fix: { GeoFix(lat: 55.701, lng: 37.4, accuracy: 5, timestamp: Date()) })
        XCTAssertEqual(reloaded.measure(roundId: "r", holeIndex: 0, targetUid: "u")?.previousIndex, 2)
    }

    func testClearRemovesMark() {
        let rangefinder = makeRangefinder(fix: { GeoFix(lat: 55.7, lng: 37.4, accuracy: 5, timestamp: Date()) })
        rangefinder.markShot(roundId: "r", holeIndex: 0, targetUid: "u", shotIndex: 0)
        rangefinder.clear(roundId: "r", holeIndex: 0, targetUid: "u")
        XCTAssertNil(rangefinder.measure(roundId: "r", holeIndex: 0, targetUid: "u"))
    }
}
