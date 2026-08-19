// ios/SmartGolfCaddyTests/HoleTrackerViewModelTests.swift
import XCTest
@testable import SmartGolfCaddy

final class HoleTrackerViewModelTests: XCTestCase {

    @MainActor
    func testDisplayedClubsPrefersOptimisticUntilServerEchoes() {
        let model = HoleTrackerViewModel(roundId: "r", holeIndex: 0, userId: "u")
        model.optimistic = .init(slot: "0:u", clubs: ["Driver", "7i"], awaitingKey: "Driver|7i")
        // Сервер ещё показывает старое (1 удар) — оверлей впереди
        XCTAssertEqual(model.displayedClubs(serverClubs: ["Driver"], pendingClubs: nil), ["Driver", "7i"])
        // Сервер отэхоил — оверлей перестаёт применяться
        XCTAssertEqual(model.displayedClubs(serverClubs: ["Driver", "7i"], pendingClubs: nil), ["Driver", "7i"])
    }

    @MainActor
    func testDisplayedClubsIgnoresForeignSlotOverlay() {
        let model = HoleTrackerViewModel(roundId: "r", holeIndex: 3, userId: "u")
        model.optimistic = .init(slot: "0:u", clubs: ["Driver", "7i"], awaitingKey: "Driver|7i")
        // Оверлей другого слота (лунка 0) не протекает в лунку 3
        XCTAssertEqual(model.displayedClubs(serverClubs: [], pendingClubs: nil), [])
    }

    @MainActor
    func testDisplayedClubsFallsBackToPendingQueue() {
        let model = HoleTrackerViewModel(roundId: "r", holeIndex: 0, userId: "u")
        XCTAssertEqual(model.displayedClubs(serverClubs: [], pendingClubs: ["PW"]), ["PW"])
    }

    @MainActor
    func testDistancesDerivedLikeClubs() {
        let model = HoleTrackerViewModel(roundId: "r", holeIndex: 0, userId: "u")
        model.optimistic = .init(slot: "0:u", clubs: ["Driver", "7i"],
                                 distances: [215, 0], awaitingKey: "Driver|7i")
        XCTAssertEqual(model.displayedDistances(serverDistances: [0], pendingDistances: nil,
                                                serverClubs: ["Driver"], pendingClubs: nil), [215, 0])
    }

    @MainActor
    func testDistancesFallBackToServerWhenEchoed() {
        let model = HoleTrackerViewModel(roundId: "r", holeIndex: 0, userId: "u")
        model.optimistic = .init(slot: "0:u", clubs: ["Driver"], distances: [0], awaitingKey: "Driver")
        // сервер отэхоил и знает дистанцию — показываем серверную
        XCTAssertEqual(model.displayedDistances(serverDistances: [215], pendingDistances: nil,
                                                serverClubs: ["Driver"], pendingClubs: nil), [215])
    }

    @MainActor
    func testSlotKeyFollowsActiveUser() {
        let model = HoleTrackerViewModel(roundId: "r", holeIndex: 2, userId: "host")
        XCTAssertEqual(model.slotKey, "2:host")
        model.setActiveUser("mate")
        XCTAssertEqual(model.slotKey, "2:mate")
    }

    @MainActor
    func testDistancesMeasuredOnlyForOwnSlot() {
        let model = HoleTrackerViewModel(roundId: "r", holeIndex: 0, userId: "host")
        XCTAssertTrue(model.measuresDistances)      // свой слот
        model.setActiveUser("mate")
        XCTAssertFalse(model.measuresDistances)     // чужой слот — координаты не мои
    }

    @MainActor
    func testReselectingSameUserKeepsOptimistic() {
        let model = HoleTrackerViewModel(roundId: "r", holeIndex: 0, userId: "host")
        model.optimistic = .init(slot: "0:host", clubs: ["Driver"], distances: [0], awaitingKey: "Driver")
        model.setActiveUser("host")
        XCTAssertNotNil(model.optimistic)          // тот же игрок — оверлей жив
        model.setActiveUser("mate")
        XCTAssertNil(model.optimistic)             // смена игрока — сброс
    }

    @MainActor
    func testGreenDistanceNilWithoutMarks() {
        let model = HoleTrackerViewModel(roundId: "r", holeIndex: 0, userId: "u")
        model.applyGreenMarks([], fix: GeoFix(lat: 55.7, lng: 37.4, accuracy: 5, timestamp: Date()))
        XCTAssertNil(model.greenDistanceMeters)
    }

    @MainActor
    func testGreenDistanceComputedFromAveragedMarks() {
        let model = HoleTrackerViewModel(roundId: "r", holeIndex: 0, userId: "u")  // лунка 1
        let sets = [GreenMarkSet(holes: [1: GreenMark(lat: 55.701, lng: 37.400)])]
        model.applyGreenMarks(sets, fix: GeoFix(lat: 55.700, lng: 37.400, accuracy: 5, timestamp: Date()))
        XCTAssertEqual(Double(model.greenDistanceMeters ?? 0), 111, accuracy: 3)
    }

    @MainActor
    func testStaleFixHidesGreenDistance() {
        let model = HoleTrackerViewModel(roundId: "r", holeIndex: 0, userId: "u")
        let old = GeoFix(lat: 55.700, lng: 37.400, accuracy: 5,
                         timestamp: Date().addingTimeInterval(-300))
        model.applyGreenMarks([GreenMarkSet(holes: [1: GreenMark(lat: 55.701, lng: 37.4)])], fix: old)
        XCTAssertNil(model.greenDistanceMeters)
    }
}
