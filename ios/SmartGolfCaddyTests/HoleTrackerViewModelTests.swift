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
}
