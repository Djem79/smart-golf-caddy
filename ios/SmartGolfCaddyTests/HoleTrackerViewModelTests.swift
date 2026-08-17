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
}
