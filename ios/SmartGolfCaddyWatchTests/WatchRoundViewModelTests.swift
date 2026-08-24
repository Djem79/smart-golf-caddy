// ios/SmartGolfCaddyWatchTests/WatchRoundViewModelTests.swift
// Тесты WatchRoundViewModel (Task 3, Phase 3c) — чистая логика без
// WatchConnectivity: снимок подаётся конструктором/apply(snapshot:).
import XCTest
@testable import SmartGolfCaddyWatch

@MainActor
final class WatchRoundViewModelTests: XCTestCase {

    private func makeSnapshot(
        totalHoles: Int = 18,
        holes: [WatchHole]? = nil,
        clubs: [String] = ["Driver", "7 Iron", "Putter"],
        activeHoleNumber: Int = 3
    ) -> WatchRoundSnapshot {
        let resolvedHoles = holes ?? (1...totalHoles).map {
            WatchHole(number: $0, par: 4, distanceMeters: 300, myShots: 0)
        }
        return WatchRoundSnapshot(
            roundId: "round-1",
            courseName: "Test Course",
            totalHoles: totalHoles,
            holes: resolvedHoles,
            clubs: clubs,
            greens: [:],
            activeHoleNumber: activeHoleNumber,
            unitsYards: false,
            updatedAt: Date()
        )
    }

    // MARK: - removeShot не уходит в минус

    func testRemoveShotDoesNotGoNegative() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot())
        XCTAssertEqual(vm.shots.count, 0)
        vm.removeShot()
        vm.removeShot()
        XCTAssertEqual(vm.shots.count, 0)
    }

    func testAddThenRemoveShot() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot())
        vm.addShot()
        vm.addShot()
        XCTAssertEqual(vm.shots.count, 2)
        vm.removeShot()
        XCTAssertEqual(vm.shots.count, 1)
        vm.removeShot()
        vm.removeShot()
        XCTAssertEqual(vm.shots.count, 0)
    }

    // MARK: - Удары сохраняются при переходе туда-обратно по лункам

    func testShotsPersistAcrossHoleNavigation() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(activeHoleNumber: 3))
        vm.addShot()
        vm.addShot()
        XCTAssertEqual(vm.shots.count, 2)

        vm.nextHole()
        XCTAssertEqual(vm.holeNumber, 4)
        XCTAssertEqual(vm.shots.count, 0, "новая лунка начинается без ударов")

        vm.addShot()
        XCTAssertEqual(vm.shots.count, 1)

        vm.previousHole()
        XCTAssertEqual(vm.holeNumber, 3)
        XCTAssertEqual(vm.shots.count, 2, "удары лунки 3 не потерялись при уходе на лунку 4")

        vm.nextHole()
        XCTAssertEqual(vm.holeNumber, 4)
        XCTAssertEqual(vm.shots.count, 1, "удары лунки 4 тоже сохранились")
    }

    // MARK: - Кламп границ лунки

    func testNextHoleClampsAtTotalHoles() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(totalHoles: 3, activeHoleNumber: 3))
        vm.nextHole()
        vm.nextHole()
        XCTAssertEqual(vm.holeNumber, 3)
    }

    func testPreviousHoleClampsAtOne() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(totalHoles: 18, activeHoleNumber: 1))
        vm.previousHole()
        vm.previousHole()
        XCTAssertEqual(vm.holeNumber, 1)
    }

    // MARK: - pendingCount

    func testPendingCountReflectsShotsBeyondConfirmed() {
        let holes = [
            WatchHole(number: 1, par: 4, distanceMeters: 300, myShots: 0),
            WatchHole(number: 2, par: 3, distanceMeters: 150, myShots: 1),
        ]
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(totalHoles: 2, holes: holes, activeHoleNumber: 2))
        // Лунка 2: сервер уже подтвердил 1 удар (сид placeholder-ом), pending 0.
        XCTAssertEqual(vm.shots.count, 1)
        XCTAssertEqual(vm.pendingCount, 0)

        vm.addShot()
        XCTAssertEqual(vm.shots.count, 2)
        XCTAssertEqual(vm.pendingCount, 1, "один удар сверх подтверждённого сервером")
    }

    func testPendingCountZeroWhenNoLocalShots() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot())
        XCTAssertEqual(vm.pendingCount, 0)
    }

    // MARK: - Применение снимка не теряет неподтверждённые локальные удары

    func testApplySnapshotDoesNotLoseUnconfirmedLocalShots() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(activeHoleNumber: 3))
        vm.addShot()
        vm.addShot()
        XCTAssertEqual(vm.shots.count, 2)

        // Новый снимок с телефона — та же лунка, сервер ещё НЕ подтвердил удары
        // (myShots всё ещё 0, например, батч ещё не долетел/не обработан).
        vm.apply(snapshot: makeSnapshot(activeHoleNumber: 3))

        XCTAssertEqual(vm.shots.count, 2, "локальные неподтверждённые удары не должны исчезать")
        XCTAssertEqual(vm.pendingCount, 2)
    }

    func testApplySnapshotSeedsNewlySeenHoleFromServerCount() {
        let vm = WatchRoundViewModel(snapshot: nil)
        XCTAssertNil(vm.currentHole)

        let holes = [WatchHole(number: 1, par: 4, distanceMeters: 300, myShots: 2)]
        vm.apply(snapshot: makeSnapshot(totalHoles: 1, holes: holes, activeHoleNumber: 1))

        XCTAssertEqual(vm.holeNumber, 1)
        XCTAssertEqual(vm.currentHole?.par, 4)
    }

    // MARK: - addShot без выбранной клюшки берёт разумный дефолт

    func testAddShotWithoutSelectionUsesFirstBagClub() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(clubs: ["Driver", "7 Iron", "Putter"]))
        XCTAssertNil(vm.selectedClub)
        vm.addShot()
        XCTAssertEqual(vm.shots, ["Driver"])
    }

    func testAddShotWithoutSelectionReusesLastUsedClub() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(clubs: ["Driver", "7 Iron", "Putter"]))
        vm.selectedClub = "7 Iron"
        vm.addShot()
        XCTAssertEqual(vm.shots, ["7 Iron"])

        vm.selectedClub = nil
        vm.addShot()
        XCTAssertEqual(vm.shots, ["7 Iron", "7 Iron"], "без явного выбора повторяем последнюю использованную клюшку")
    }

    func testAddShotWithEmptyBagIsNoOp() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(clubs: []))
        vm.addShot()
        XCTAssertEqual(vm.shots.count, 0)
    }

    // MARK: - currentHole / clubs

    func testCurrentHoleAndClubsReflectSnapshot() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(clubs: ["Driver", "Putter"], activeHoleNumber: 5))
        XCTAssertEqual(vm.currentHole?.number, 5)
        XCTAssertEqual(vm.clubs, ["Driver", "Putter"])
    }

    func testNoSnapshotYieldsEmptyState() {
        let vm = WatchRoundViewModel(snapshot: nil)
        XCTAssertNil(vm.currentHole)
        XCTAssertEqual(vm.clubs, [])
        XCTAssertEqual(vm.holeNumber, 1)
        vm.nextHole()
        XCTAssertEqual(vm.holeNumber, 1, "без снимка навигация не двигается")
    }
}
