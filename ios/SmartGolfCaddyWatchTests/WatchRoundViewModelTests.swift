// ios/SmartGolfCaddyWatchTests/WatchRoundViewModelTests.swift
// Тесты WatchRoundViewModel (Task 3, Phase 3c) — чистая логика без
// WatchConnectivity: снимок подаётся конструктором/apply(snapshot:).
// Task 4 добавляет проверку интеграции с WatchShotQueue: addShot()/
// removeShot() обязаны держать очередь синхронной с unsyncedShots(forHole:).
import XCTest
@testable import SmartGolfCaddyWatch

@MainActor
final class WatchRoundViewModelTests: XCTestCase {

    private var queueStoreURL: URL!
    private var confirmedStoreURL: URL!

    override func setUp() {
        super.setUp()
        let id = UUID().uuidString
        queueStoreURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchroundvm-queue-test-\(id).json")
        confirmedStoreURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchroundvm-confirmed-test-\(id).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: queueStoreURL)
        try? FileManager.default.removeItem(at: confirmedStoreURL)
        super.tearDown()
    }

    /// Изолированная (файл во временной директории) очередь для тестов,
    /// которые инспектируют её содержимое — не трогает WatchShotQueue.shared.
    private func makeQueue() -> WatchShotQueue {
        WatchShotQueue(storeURL: queueStoreURL, confirmedStoreURL: confirmedStoreURL)
    }

    /// markConfirmed постит `.watchShotSyncFailed` наблюдателям на
    /// queue: .main — доставка НЕ синхронна с постом (OperationQueue.main
    /// планирует блок, а не выполняет инлайн, даже если пост случился на
    /// главном потоке). Заказываем ЕЩЁ ОДИН блок на main ПОСЛЕ поста и
    /// ждём его — та же серийная очередь гарантирует FIFO, так что к
    /// моменту его выполнения обработчик VM уже отработал.
    private func drainMainQueue() {
        let exp = expectation(description: "main queue drained")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1)
    }

    private func makeSnapshot(
        roundId: String = "round-1",
        totalHoles: Int = 18,
        holes: [WatchHole]? = nil,
        clubs: [String] = ["Driver", "7 Iron", "Putter"],
        activeHoleNumber: Int = 3
    ) -> WatchRoundSnapshot {
        let resolvedHoles = holes ?? (1...totalHoles).map {
            WatchHole(number: $0, par: 4, distanceMeters: 300, myShots: 0)
        }
        return WatchRoundSnapshot(
            roundId: roundId,
            courseName: "Test Course",
            totalHoles: totalHoles,
            holes: resolvedHoles,
            clubs: clubs,
            greens: [:],
            activeHoleNumber: activeHoleNumber,
            units: .m,
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

    // MARK: - Смена раунда сбрасывает локальные удары (review fix 1)

    func testApplySnapshotForNewRoundDoesNotLeakShotsFromPreviousRound() {
        // Раунд A: на лунке 5 два неподтверждённых удара (телефон офлайн,
        // myShots всё ещё 0 — батч не долетел до сервера).
        let holesA = [WatchHole(number: 5, par: 4, distanceMeters: 300, myShots: 0)]
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(roundId: "round-A", totalHoles: 5, holes: holesA, activeHoleNumber: 5))
        vm.addShot()
        vm.addShot()
        XCTAssertEqual(vm.shots.count, 2)
        XCTAssertEqual(vm.pendingCount, 2)

        // Раунд A завершён, приходит снимок раунда B — та же лунка 5, но с
        // myShots: 0 (новый раунд, ещё ничего не сыграно).
        let holesB = [WatchHole(number: 5, par: 3, distanceMeters: 150, myShots: 0)]
        vm.apply(snapshot: makeSnapshot(roundId: "round-B", totalHoles: 5, holes: holesB, activeHoleNumber: 5))

        XCTAssertEqual(vm.shots.count, 0, "удары раунда A не должны быть видны в раунде B")
        XCTAssertEqual(vm.pendingCount, 0, "не должно быть фантомных неподтверждённых ударов")
        XCTAssertEqual(vm.currentHole?.par, 3, "текущая лунка теперь описывается снимком раунда B")
    }

    func testApplySnapshotForNewRoundResetsHoleNumberToNewActiveHole() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(roundId: "round-A", totalHoles: 18, activeHoleNumber: 3))
        vm.nextHole()
        vm.nextHole()
        XCTAssertEqual(vm.holeNumber, 5)

        vm.apply(snapshot: makeSnapshot(roundId: "round-B", totalHoles: 18, activeHoleNumber: 1))

        XCTAssertEqual(vm.holeNumber, 1, "лунка часов пересчитана из activeHoleNumber нового раунда")
    }

    func testApplySnapshotForNewRoundClearsSelectedAndLastUsedClub() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(roundId: "round-A", clubs: ["Driver", "Putter"]))
        vm.selectedClub = "Putter"
        vm.addShot()
        XCTAssertEqual(vm.selectedClub, "Putter")

        vm.apply(snapshot: makeSnapshot(roundId: "round-B", clubs: ["Driver", "Putter"]))

        XCTAssertNil(vm.selectedClub, "выбор клюшки прошлого раунда не должен переживать смену раунда")
        vm.addShot()
        XCTAssertEqual(vm.shots, ["Driver"], "addShot() в новом раунде не должен унаследовать lastUsedClub старого")
    }

    func testApplySnapshotForSameRoundDoesNotResetLocalState() {
        // Регрессия: убеждаемся, что фикс 1 не сломал исходное поведение —
        // тот же roundId по-прежнему НЕ сбрасывает локальные удары.
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(roundId: "round-A", activeHoleNumber: 3))
        vm.addShot()
        vm.apply(snapshot: makeSnapshot(roundId: "round-A", activeHoleNumber: 3))
        XCTAssertEqual(vm.shots.count, 1)
    }

    // MARK: - unsyncedShots(forHole:) — только реально введённый на часах хвост (review fix 2)

    func testUnsyncedShotsReturnsOnlyLocallyAddedTail() {
        // Сервер уже подтвердил 3 удара на лунке 4 (введены на телефоне) —
        // seedIfNeeded подставит 3 плейсхолдера. На часах добавляем ЕЩЁ один
        // удар выбранной клюшкой.
        let holes = [WatchHole(number: 4, par: 5, distanceMeters: 480, myShots: 3)]
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(totalHoles: 4, holes: holes, clubs: ["Driver", "3 Wood"], activeHoleNumber: 4))
        XCTAssertEqual(vm.shots.count, 3, "3 плейсхолдера от seedIfNeeded")

        vm.selectedClub = "3 Wood"
        vm.addShot()
        XCTAssertEqual(vm.shots.count, 4)

        let unsynced = vm.unsyncedShots(forHole: 4)
        XCTAssertEqual(unsynced, ["3 Wood"], "только реально выбранная на часах клюшка, без плейсхолдеров")
    }

    func testUnsyncedShotsEmptyWhenAllConfirmed() {
        let holes = [WatchHole(number: 1, par: 4, distanceMeters: 300, myShots: 2)]
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(totalHoles: 1, holes: holes, activeHoleNumber: 1))
        XCTAssertEqual(vm.unsyncedShots(forHole: 1), [])
    }

    func testNoSnapshotYieldsEmptyState() {
        let vm = WatchRoundViewModel(snapshot: nil)
        XCTAssertNil(vm.currentHole)
        XCTAssertEqual(vm.clubs, [])
        XCTAssertEqual(vm.holeNumber, 1)
        vm.nextHole()
        XCTAssertEqual(vm.holeNumber, 1, "без снимка навигация не двигается")
    }

    // MARK: - addShot() кладёт удар в WatchShotQueue (Task 4)

    func testAddShotEnqueuesUnsyncedTailIntoWatchQueue() {
        let queue = makeQueue()
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(roundId: "round-1", activeHoleNumber: 3), shotQueue: queue)

        vm.addShot()

        XCTAssertEqual(queue.pending.count, 1)
        XCTAssertEqual(queue.pending.first?.roundId, "round-1")
        XCTAssertEqual(queue.pending.first?.holeNumber, 3)
        XCTAssertEqual(queue.pending.first?.clubs, ["Driver"])
    }

    func testRepeatedAddShotGrowsQueueTailWithoutDuplicatingSlot() {
        let queue = makeQueue()
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(roundId: "round-1", activeHoleNumber: 3), shotQueue: queue)

        vm.addShot()
        vm.addShot()

        XCTAssertEqual(queue.pending.count, 1, "один слот на лунку, не история отдельных ударов")
        XCTAssertEqual(queue.pending.first?.clubs, ["Driver", "Driver"])
    }

    // КРИТИЧЕСКИЙ ИНВАРИАНТ задачи: заглушки seedIfNeeded (плейсхолдеры по
    // уже подтверждённым сервером ударам) НИКОГДА не должны попасть в
    // очередь на отправку телефону — иначе recordShot затрёт настоящие
    // клюшки, записанные на телефоне, заглушками.
    func testPlaceholdersFromSeedNeverEnterTheQueue() {
        let queue = makeQueue()
        // Сервер уже подтвердил 3 удара на лунке 4 — seedIfNeeded подставит
        // 3 плейсхолдера ("Driver" — первая клюшка сумки).
        let holes = [WatchHole(number: 4, par: 5, distanceMeters: 480, myShots: 3)]
        let vm = WatchRoundViewModel(
            snapshot: makeSnapshot(roundId: "round-1", totalHoles: 4, holes: holes, clubs: ["Driver", "3 Wood"], activeHoleNumber: 4),
            shotQueue: queue
        )
        XCTAssertTrue(queue.pending.isEmpty, "сам факт появления снимка (init/seed) ничего не шлёт в очередь")

        vm.selectedClub = "3 Wood"
        vm.addShot()

        XCTAssertEqual(queue.pending.count, 1)
        XCTAssertEqual(queue.pending.first?.clubs, ["3 Wood"], "только реально введённый на часах удар, БЕЗ плейсхолдеров-префикса")
    }

    func testRemoveShotSyncsQueueDownToShrunkTail() {
        let queue = makeQueue()
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(roundId: "round-1", activeHoleNumber: 3), shotQueue: queue)
        vm.addShot()
        vm.addShot()
        XCTAssertEqual(queue.pending.first?.clubs, ["Driver", "Driver"])

        vm.removeShot()

        XCTAssertEqual(queue.pending.first?.clubs, ["Driver"], "удаление удара на часах отражается в очереди")
    }

    func testRemoveShotDownToFullyConfirmedClearsQueueSlot() {
        let queue = makeQueue()
        // Сервер уже подтвердил 1 удар — локально это плейсхолдер.
        let holes = [WatchHole(number: 1, par: 4, distanceMeters: 300, myShots: 1)]
        let vm = WatchRoundViewModel(
            snapshot: makeSnapshot(roundId: "round-1", totalHoles: 1, holes: holes, activeHoleNumber: 1),
            shotQueue: queue
        )
        vm.addShot()
        XCTAssertEqual(queue.pending.first?.clubs, ["Driver"])

        vm.removeShot()  // возвращаемся ровно к подтверждённому серверу состоянию

        XCTAssertTrue(queue.pending.isEmpty, "хвост пуст — нечего слать, слот снят")
    }

    func testAddShotWithoutSnapshotDoesNotTouchQueue() {
        let queue = makeQueue()
        let vm = WatchRoundViewModel(snapshot: nil, shotQueue: queue)
        vm.addShot()
        XCTAssertTrue(queue.pending.isEmpty)
    }

    // MARK: - greenDistanceMeters (Task 5) — те же гейты, что у
    // ShotRangefinder.isUsable на телефоне: точность ≤25 м, возраст ≤90 с,
    // диапазон 0…800 м. currentFix подаётся снаружи (не CoreLocation).

    // ~111 м на север при 0.001° широты — тот же приём, что и в
    // ShotRangefinderTests.testMeasureBetweenTwoFixes.

    func testGreenDistanceComputedWithUsableFix() {
        let holes = [WatchHole(number: 3, par: 4, distanceMeters: 300, myShots: 0)]
        let snapshot = WatchRoundSnapshot(
            roundId: "round-1", courseName: "Test", totalHoles: 4, holes: holes,
            clubs: ["Driver"], greens: [3: GreenMark(lat: 55.700000, lng: 37.400000)],
            activeHoleNumber: 3, units: .m, updatedAt: Date()
        )
        let vm = WatchRoundViewModel(snapshot: snapshot)
        vm.currentFix = GeoFix(lat: 55.701000, lng: 37.400000, accuracy: 5, timestamp: Date())
        XCTAssertEqual(Double(vm.greenDistanceMeters ?? 0), 111, accuracy: 3)
    }

    func testGreenDistanceNilWithoutFix() {
        let holes = [WatchHole(number: 3, par: 4, distanceMeters: 300, myShots: 0)]
        let snapshot = WatchRoundSnapshot(
            roundId: "round-1", courseName: "Test", totalHoles: 4, holes: holes,
            clubs: ["Driver"], greens: [3: GreenMark(lat: 55.700000, lng: 37.400000)],
            activeHoleNumber: 3, units: .m, updatedAt: Date()
        )
        let vm = WatchRoundViewModel(snapshot: snapshot)
        XCTAssertNil(vm.greenDistanceMeters)
    }

    func testGreenDistanceNilWhenAccuracyPoor() {
        let holes = [WatchHole(number: 3, par: 4, distanceMeters: 300, myShots: 0)]
        let snapshot = WatchRoundSnapshot(
            roundId: "round-1", courseName: "Test", totalHoles: 4, holes: holes,
            clubs: ["Driver"], greens: [3: GreenMark(lat: 55.700000, lng: 37.400000)],
            activeHoleNumber: 3, units: .m, updatedAt: Date()
        )
        let vm = WatchRoundViewModel(snapshot: snapshot)
        vm.currentFix = GeoFix(lat: 55.701000, lng: 37.400000, accuracy: 60, timestamp: Date())
        XCTAssertNil(vm.greenDistanceMeters, "точность хуже 25 м — недостоверно")
    }

    func testGreenDistanceNilWhenFixStale() {
        let holes = [WatchHole(number: 3, par: 4, distanceMeters: 300, myShots: 0)]
        let snapshot = WatchRoundSnapshot(
            roundId: "round-1", courseName: "Test", totalHoles: 4, holes: holes,
            clubs: ["Driver"], greens: [3: GreenMark(lat: 55.700000, lng: 37.400000)],
            activeHoleNumber: 3, units: .m, updatedAt: Date()
        )
        let vm = WatchRoundViewModel(snapshot: snapshot)
        vm.currentFix = GeoFix(lat: 55.701000, lng: 37.400000, accuracy: 5, timestamp: Date().addingTimeInterval(-300))
        XCTAssertNil(vm.greenDistanceMeters, "фикс 5 минут назад — экран лежал заблокированным, трекинг стоял")
    }

    func testGreenDistanceNilWhenNoGreenMarkForHole() {
        let holes = [WatchHole(number: 3, par: 4, distanceMeters: 300, myShots: 0)]
        let snapshot = WatchRoundSnapshot(
            roundId: "round-1", courseName: "Test", totalHoles: 4, holes: holes,
            clubs: ["Driver"], greens: [:],
            activeHoleNumber: 3, units: .m, updatedAt: Date()
        )
        let vm = WatchRoundViewModel(snapshot: snapshot)
        vm.currentFix = GeoFix(lat: 55.700000, lng: 37.400000, accuracy: 5, timestamp: Date())
        XCTAssertNil(vm.greenDistanceMeters, "поле не отмечено ни одним игроком — метки для лунки нет")
    }

    func testGreenDistanceNilBeyondClampRange() {
        let holes = [WatchHole(number: 3, par: 4, distanceMeters: 300, myShots: 0)]
        // ~1.1 км на север (0.01° широты) — за пределами разумного 0…800 м,
        // тот же клэмп, что и в HoleTrackerViewModel.applyGreenMarks на телефоне.
        let snapshot = WatchRoundSnapshot(
            roundId: "round-1", courseName: "Test", totalHoles: 4, holes: holes,
            clubs: ["Driver"], greens: [3: GreenMark(lat: 55.710000, lng: 37.400000)],
            activeHoleNumber: 3, units: .m, updatedAt: Date()
        )
        let vm = WatchRoundViewModel(snapshot: snapshot)
        vm.currentFix = GeoFix(lat: 55.700000, lng: 37.400000, accuracy: 5, timestamp: Date())
        XCTAssertNil(vm.greenDistanceMeters, "больше 800 м — чужое поле или мусорная метка")
    }

    func testGreenDistanceChangesWithHoleNavigation() {
        let holes = [
            WatchHole(number: 3, par: 4, distanceMeters: 300, myShots: 0),
            WatchHole(number: 4, par: 3, distanceMeters: 150, myShots: 0),
        ]
        let snapshot = WatchRoundSnapshot(
            roundId: "round-1", courseName: "Test", totalHoles: 4, holes: holes,
            clubs: ["Driver"],
            greens: [3: GreenMark(lat: 55.701000, lng: 37.400000), 4: GreenMark(lat: 55.702000, lng: 37.400000)],
            activeHoleNumber: 3, units: .m, updatedAt: Date()
        )
        let vm = WatchRoundViewModel(snapshot: snapshot)
        vm.currentFix = GeoFix(lat: 55.700000, lng: 37.400000, accuracy: 5, timestamp: Date())

        let distanceHole3 = vm.greenDistanceMeters
        XCTAssertEqual(Double(distanceHole3 ?? 0), 111, accuracy: 3)

        vm.nextHole()
        XCTAssertEqual(vm.holeNumber, 4)
        let distanceHole4 = vm.greenDistanceMeters
        XCTAssertEqual(Double(distanceHole4 ?? 0), 222, accuracy: 3)
        XCTAssertNotEqual(distanceHole3, distanceHole4, "смена лунки меняет дистанцию до грина")
    }

    // MARK: - Fix 2 (живое ревью Task 4): квитанция, а не снимок, двигает
    // confirmedCount — иначе устаревший снимок (телефон в кармане, экран
    // закрыт) заставляет unsyncedShots() повторно отдать уже подтверждённый
    // удар, и телефон дописывает его на сервере ВТОРОЙ раз.

    func testConfirmedCountAdvancesFromReceiptEvenWithoutFreshSnapshot() {
        let queue = makeQueue()
        // Сервер уже подтвердил 2 удара на лунке 1 (сид placeholder-ами).
        let holes = [WatchHole(number: 1, par: 4, distanceMeters: 300, myShots: 2)]
        let vm = WatchRoundViewModel(
            snapshot: makeSnapshot(roundId: "round-1", totalHoles: 1, holes: holes,
                                   clubs: ["Driver", "7 Iron", "Putter"], activeHoleNumber: 1),
            shotQueue: queue
        )
        XCTAssertEqual(vm.shots.count, 2, "2 плейсхолдера от seedIfNeeded")

        vm.addShot()  // 3-й, реальный
        XCTAssertEqual(vm.unsyncedShots(forHole: 1).count, 1)

        // Телефон принял этот батч и прислал квитанцию — ИМИТИРУЕМ
        // напрямую через queue (в проде приходит через
        // PhoneBridge.session(_:didReceiveUserInfo:)). Снимок на часах
        // НЕ обновился (myShots в vm.snapshot всё ещё 2) — телефон лежит
        // в кармане, sendWatchSnapshot() не вызывался.
        queue.markConfirmed(roundId: "round-1", holeNumber: 1, acceptedCount: 1)

        vm.addShot()  // 4-й
        XCTAssertEqual(vm.shots.count, 4)
        XCTAssertEqual(
            vm.unsyncedShots(forHole: 1).count, 1,
            "без фикса confirmedCount остался бы 2 (из устаревшего снимка), unsyncedShots вернул бы 2 элемента — телефон дописал бы 3-й удар второй раз"
        )
    }

    func testConfirmedCountUsesMaxOfSnapshotAndReceipt() {
        // Снимок ВСЁ ЖЕ обновился и оказался ВПЕРЕДИ локального счётчика
        // квитанций (например, кто-то другой записал удар за игрока на
        // телефоне) — confirmedCount не должен откатываться назад.
        let queue = makeQueue()
        let holes = [WatchHole(number: 1, par: 4, distanceMeters: 300, myShots: 5)]
        let vm = WatchRoundViewModel(
            snapshot: makeSnapshot(roundId: "round-1", totalHoles: 1, holes: holes, activeHoleNumber: 1),
            shotQueue: queue
        )
        queue.markConfirmed(roundId: "round-1", holeNumber: 1, acceptedCount: 1)
        XCTAssertEqual(vm.pendingCount, 0, "snapshot.myShots(5) > shotQueue.confirmedCount(1) — берём максимум")
    }

    func testConfirmedCountResetsOnRoundChange() {
        let queue = makeQueue()
        queue.markConfirmed(roundId: "round-A", holeNumber: 1, acceptedCount: 3)
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(roundId: "round-A"), shotQueue: queue)
        vm.apply(snapshot: makeSnapshot(roundId: "round-B"))
        XCTAssertEqual(queue.confirmedCount(roundId: "round-A", holeNumber: 1), 0, "счётчики старого раунда очищены (гигиена)")
    }

    // MARK: - Fix 3 (живое ревью Task 4): окончательный отказ сервера
    // показывает явную ошибку вместо бесконечного "не синхронизировано".

    func testSyncFailedNotificationMarksCurrentHoleAsFailed() {
        let queue = makeQueue()
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(roundId: "round-1", activeHoleNumber: 2), shotQueue: queue)
        XCTAssertFalse(vm.currentHoleSyncFailed)

        queue.markConfirmed(roundId: "round-1", holeNumber: 2, acceptedCount: 1, accepted: false)
        drainMainQueue()

        XCTAssertTrue(vm.currentHoleSyncFailed)
    }

    func testSyncFailedIgnoresNotificationForDifferentRound() {
        let queue = makeQueue()
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(roundId: "round-1", activeHoleNumber: 2), shotQueue: queue)

        queue.markConfirmed(roundId: "round-OTHER", holeNumber: 2, acceptedCount: 1, accepted: false)
        drainMainQueue()

        XCTAssertFalse(vm.currentHoleSyncFailed, "квитанция чужого раунда не должна помечать текущую лунку")
    }

    func testAddShotClearsSyncFailedOnRetry() {
        let queue = makeQueue()
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(roundId: "round-1", clubs: ["Driver"], activeHoleNumber: 2), shotQueue: queue)
        queue.markConfirmed(roundId: "round-1", holeNumber: 2, acceptedCount: 1, accepted: false)
        drainMainQueue()
        XCTAssertTrue(vm.currentHoleSyncFailed)

        vm.addShot()

        XCTAssertFalse(vm.currentHoleSyncFailed, "новая попытка на лунке — чистый старт для индикатора ошибки")
    }

    func testSyncFailedResetsOnRoundChange() {
        let queue = makeQueue()
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(roundId: "round-A", activeHoleNumber: 2), shotQueue: queue)
        queue.markConfirmed(roundId: "round-A", holeNumber: 2, acceptedCount: 1, accepted: false)
        drainMainQueue()
        XCTAssertTrue(vm.currentHoleSyncFailed)

        vm.apply(snapshot: makeSnapshot(roundId: "round-B", activeHoleNumber: 2))

        XCTAssertFalse(vm.currentHoleSyncFailed)
    }
}
