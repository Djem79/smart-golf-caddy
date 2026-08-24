// ios/SmartGolfCaddyWatchTests/WatchRoundViewModelTests.swift
// Тесты WatchRoundViewModel — чистая логика без WatchConnectivity: снимок
// подаётся конструктором/apply(snapshot:).
//
// МОДЕЛЬ (см. заголовок WatchRoundViewModel.swift): НЕТ in-memory кэша
// клюшек по лункам и НЕТ confirmedCount. `pendingClubs`/`unsyncedShots`
// читают WatchShotQueue.pending напрямую при каждом обращении;
// `shotCount` = snapshot.myShots + pendingClubs.count. addShot() всегда
// дописывает в durable-очередь (никогда не no-op), removeShot() снимает
// только из локального хвоста (no-op, если он пуст — не трогает
// серверные удары).
import XCTest
@testable import SmartGolfCaddyWatch

@MainActor
final class WatchRoundViewModelTests: XCTestCase {

    private var queueStoreURL: URL!
    private var sequenceStoreURL: URL!
    private var installIdStoreURL: URL!

    override func setUp() {
        super.setUp()
        let id = UUID().uuidString
        queueStoreURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchroundvm-queue-test-\(id).json")
        sequenceStoreURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchroundvm-sequence-test-\(id).json")
        installIdStoreURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("watchroundvm-installid-test-\(id).txt")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: queueStoreURL)
        try? FileManager.default.removeItem(at: sequenceStoreURL)
        try? FileManager.default.removeItem(at: installIdStoreURL)
        super.tearDown()
    }

    /// Изолированная (файл во временной директории) очередь для тестов,
    /// которые инспектируют её содержимое — не трогает WatchShotQueue.shared.
    private func makeQueue() -> WatchShotQueue {
        WatchShotQueue(storeURL: queueStoreURL, sequenceStoreURL: sequenceStoreURL, installIdStoreURL: installIdStoreURL)
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

    // MARK: - removeShot не уходит в минус (и не трогает сервер)

    func testRemoveShotDoesNotGoNegative() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(), shotQueue: makeQueue())
        XCTAssertEqual(vm.pendingClubs.count, 0)
        vm.removeShot()
        vm.removeShot()
        XCTAssertEqual(vm.pendingClubs.count, 0)
    }

    func testAddThenRemoveShot() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(), shotQueue: makeQueue())
        vm.addShot()
        vm.addShot()
        XCTAssertEqual(vm.pendingClubs.count, 2)
        vm.removeShot()
        XCTAssertEqual(vm.pendingClubs.count, 1)
        vm.removeShot()
        vm.removeShot()
        XCTAssertEqual(vm.pendingClubs.count, 0)
    }

    // MARK: - Хвост лунки сохраняется при переходе туда-обратно (durable,
    // не зависит от того, какая лунка сейчас "активна" на экране)

    func testShotsPersistAcrossHoleNavigation() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(activeHoleNumber: 3), shotQueue: makeQueue())
        vm.addShot()
        vm.addShot()
        XCTAssertEqual(vm.pendingClubs.count, 2)

        vm.nextHole()
        XCTAssertEqual(vm.holeNumber, 4)
        XCTAssertEqual(vm.pendingClubs.count, 0, "новая лунка начинается без ударов")

        vm.addShot()
        XCTAssertEqual(vm.pendingClubs.count, 1)

        vm.previousHole()
        XCTAssertEqual(vm.holeNumber, 3)
        XCTAssertEqual(vm.pendingClubs.count, 2, "удары лунки 3 не потерялись при уходе на лунку 4")

        vm.nextHole()
        XCTAssertEqual(vm.holeNumber, 4)
        XCTAssertEqual(vm.pendingClubs.count, 1, "удары лунки 4 тоже сохранились")
    }

    // MARK: - Кламп границ лунки

    func testNextHoleClampsAtTotalHoles() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(totalHoles: 3, activeHoleNumber: 3), shotQueue: makeQueue())
        vm.nextHole()
        vm.nextHole()
        XCTAssertEqual(vm.holeNumber, 3)
    }

    func testPreviousHoleClampsAtOne() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(totalHoles: 18, activeHoleNumber: 1), shotQueue: makeQueue())
        vm.previousHole()
        vm.previousHole()
        XCTAssertEqual(vm.holeNumber, 1)
    }

    // MARK: - pendingCount / shotCount

    func testPendingCountEqualsLocalTailLength() {
        let holes = [
            WatchHole(number: 1, par: 4, distanceMeters: 300, myShots: 0),
            WatchHole(number: 2, par: 3, distanceMeters: 150, myShots: 1),
        ]
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(totalHoles: 2, holes: holes, activeHoleNumber: 2), shotQueue: makeQueue())
        // Лунка 2: сервер подтвердил 1 удар, локального хвоста ещё нет.
        XCTAssertEqual(vm.pendingCount, 0)
        XCTAssertEqual(vm.shotCount, 1, "1 сервер + 0 в очереди")

        vm.addShot()
        XCTAssertEqual(vm.pendingCount, 1, "ровно длина локального хвоста — без вычитания confirmedCount")
        XCTAssertEqual(vm.shotCount, 2, "1 сервер + 1 в очереди")
    }

    func testPendingCountZeroWhenNoLocalShots() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(), shotQueue: makeQueue())
        XCTAssertEqual(vm.pendingCount, 0)
    }

    // MARK: - apply(snapshot:) в пределах ОДНОГО раунда не трогает
    // durable-хвост (он и так не в памяти — трогать там нечего)

    func testApplySnapshotDoesNotLoseUnconfirmedLocalShots() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(activeHoleNumber: 3), shotQueue: makeQueue())
        vm.addShot()
        vm.addShot()
        XCTAssertEqual(vm.pendingClubs.count, 2)

        // Новый снимок с телефона — та же лунка, сервер ещё НЕ подтвердил
        // удары (myShots всё ещё 0).
        vm.apply(snapshot: makeSnapshot(activeHoleNumber: 3))

        XCTAssertEqual(vm.pendingClubs.count, 2, "локальные неподтверждённые удары не должны исчезать")
        XCTAssertEqual(vm.pendingCount, 2)
    }

    // MARK: - Fix 6 (живое ревью Task 4): apply() на nil-стартовой VM
    // обязана пересчитать holeNumber, не полагаясь на дисциплину вызывающей
    // стороны.

    func testApplyOnNilStartVMRecomputesHoleNumberFromActiveHoleNumber() {
        let vm = WatchRoundViewModel(snapshot: nil, shotQueue: makeQueue())
        XCTAssertNil(vm.currentHole)

        // activeHoleNumber НАРОЧНО != 1 (дефолт holeNumber) — иначе тест
        // проходил бы "по совпадению", а не проверял реальный пересчёт.
        let holes = [
            WatchHole(number: 1, par: 3, distanceMeters: 150, myShots: 0),
            WatchHole(number: 2, par: 4, distanceMeters: 300, myShots: 0),
            WatchHole(number: 3, par: 5, distanceMeters: 480, myShots: 2),
        ]
        vm.apply(snapshot: makeSnapshot(totalHoles: 3, holes: holes, activeHoleNumber: 3))

        XCTAssertEqual(vm.holeNumber, 3, "holeNumber обязан пересчитаться из activeHoleNumber нового снимка даже на nil-стартовой VM")
        XCTAssertEqual(vm.currentHole?.par, 5)
    }

    // MARK: - addShot без выбранной клюшки берёт разумный дефолт

    func testAddShotWithoutSelectionUsesFirstBagClub() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(clubs: ["Driver", "7 Iron", "Putter"]), shotQueue: makeQueue())
        XCTAssertNil(vm.selectedClub)
        vm.addShot()
        XCTAssertEqual(vm.pendingClubs, ["Driver"])
    }

    func testAddShotWithoutSelectionReusesLastUsedClub() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(clubs: ["Driver", "7 Iron", "Putter"]), shotQueue: makeQueue())
        vm.selectedClub = "7 Iron"
        vm.addShot()
        XCTAssertEqual(vm.pendingClubs, ["7 Iron"])

        vm.selectedClub = nil
        vm.addShot()
        XCTAssertEqual(vm.pendingClubs, ["7 Iron", "7 Iron"], "без явного выбора повторяем последнюю использованную клюшку")
    }

    func testAddShotWithEmptyBagIsNoOp() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(clubs: []), shotQueue: makeQueue())
        vm.addShot()
        XCTAssertEqual(vm.pendingClubs.count, 0)
    }

    // MARK: - currentHole / clubs

    func testCurrentHoleAndClubsReflectSnapshot() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(clubs: ["Driver", "Putter"], activeHoleNumber: 5), shotQueue: makeQueue())
        XCTAssertEqual(vm.currentHole?.number, 5)
        XCTAssertEqual(vm.clubs, ["Driver", "Putter"])
    }

    // MARK: - Смена раунда

    func testApplySnapshotForNewRoundDoesNotLeakShotsFromPreviousRound() {
        // Раунд A: на лунке 5 два неподтверждённых удара (телефон офлайн,
        // myShots всё ещё 0 — батч не долетел до сервера).
        let holesA = [WatchHole(number: 5, par: 4, distanceMeters: 300, myShots: 0)]
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(roundId: "round-A", totalHoles: 5, holes: holesA, activeHoleNumber: 5), shotQueue: makeQueue())
        vm.addShot()
        vm.addShot()
        XCTAssertEqual(vm.pendingClubs.count, 2)
        XCTAssertEqual(vm.pendingCount, 2)

        // Раунд A завершён, приходит снимок раунда B — та же лунка 5, но с
        // myShots: 0 (новый раунд, ещё ничего не сыграно). Хвост раунда A
        // физически лежит в очереди под ключом roundId:"round-A" — сюда он
        // попасть не может: pendingClubs фильтрует по snapshot.roundId.
        let holesB = [WatchHole(number: 5, par: 3, distanceMeters: 150, myShots: 0)]
        vm.apply(snapshot: makeSnapshot(roundId: "round-B", totalHoles: 5, holes: holesB, activeHoleNumber: 5))

        XCTAssertEqual(vm.pendingClubs.count, 0, "удары раунда A не должны быть видны в раунде B")
        XCTAssertEqual(vm.pendingCount, 0, "не должно быть фантомных неподтверждённых ударов")
        XCTAssertEqual(vm.currentHole?.par, 3, "текущая лунка теперь описывается снимком раунда B")
    }

    func testApplySnapshotForNewRoundResetsHoleNumberToNewActiveHole() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(roundId: "round-A", totalHoles: 18, activeHoleNumber: 3), shotQueue: makeQueue())
        vm.nextHole()
        vm.nextHole()
        XCTAssertEqual(vm.holeNumber, 5)

        vm.apply(snapshot: makeSnapshot(roundId: "round-B", totalHoles: 18, activeHoleNumber: 1))

        XCTAssertEqual(vm.holeNumber, 1, "лунка часов пересчитана из activeHoleNumber нового раунда")
    }

    func testApplySnapshotForNewRoundClearsSelectedAndLastUsedClub() {
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(roundId: "round-A", clubs: ["Driver", "Putter"]), shotQueue: makeQueue())
        vm.selectedClub = "Putter"
        vm.addShot()
        XCTAssertEqual(vm.selectedClub, "Putter")

        vm.apply(snapshot: makeSnapshot(roundId: "round-B", clubs: ["Driver", "Putter"]))

        XCTAssertNil(vm.selectedClub, "выбор клюшки прошлого раунда не должен переживать смену раунда")
        vm.addShot()
        XCTAssertEqual(vm.pendingClubs, ["Driver"], "addShot() в новом раунде не должен унаследовать lastUsedClub старого")
    }

    func testApplySnapshotForSameRoundDoesNotResetSelectedClub() {
        // Тот же roundId НЕ сбрасывает выбор клюшки/lastUsedClub (в отличие
        // от смены раунда) — durable-хвост в любом случае не тронут apply(),
        // но тут важно именно поведение selectedClub/lastUsedClub.
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(roundId: "round-A", clubs: ["Driver", "Putter"], activeHoleNumber: 3), shotQueue: makeQueue())
        vm.selectedClub = "Putter"
        vm.addShot()
        vm.apply(snapshot: makeSnapshot(roundId: "round-A", clubs: ["Driver", "Putter"], activeHoleNumber: 3))
        XCTAssertEqual(vm.selectedClub, "Putter")
        XCTAssertEqual(vm.pendingClubs, ["Putter"])
    }

    // MARK: - unsyncedShots(forHole:) — ровно durable-хвост, без плейсхолдеров
    // структурно (нет механизма, который мог бы их туда положить)

    func testUnsyncedShotsReturnsExactlyTheDurableTail() {
        // Сервер уже подтвердил 3 удара на лунке 4 (введены на телефоне) —
        // это НЕ должно порождать никаких заглушек в очереди. На часах
        // добавляем ОДИН реальный удар.
        let holes = [WatchHole(number: 4, par: 5, distanceMeters: 480, myShots: 3)]
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(totalHoles: 4, holes: holes, clubs: ["Driver", "3 Wood"], activeHoleNumber: 4), shotQueue: makeQueue())
        XCTAssertEqual(vm.pendingClubs.count, 0, "сам факт myShots > 0 не кладёт НИЧЕГО в локальный хвост")

        vm.selectedClub = "3 Wood"
        vm.addShot()

        XCTAssertEqual(vm.unsyncedShots(forHole: 4), ["3 Wood"], "только реально введённый на часах удар")
        XCTAssertEqual(vm.shotCount, 4, "3 сервер + 1 в очереди")
    }

    func testUnsyncedShotsEmptyWhenNothingQueuedLocally() {
        let holes = [WatchHole(number: 1, par: 4, distanceMeters: 300, myShots: 2)]
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(totalHoles: 1, holes: holes, activeHoleNumber: 1), shotQueue: makeQueue())
        XCTAssertEqual(vm.unsyncedShots(forHole: 1), [])
    }

    func testNoSnapshotYieldsEmptyState() {
        let vm = WatchRoundViewModel(snapshot: nil, shotQueue: makeQueue())
        XCTAssertNil(vm.currentHole)
        XCTAssertEqual(vm.clubs, [])
        XCTAssertEqual(vm.holeNumber, 1)
        XCTAssertEqual(vm.pendingClubs, [])
        vm.nextHole()
        XCTAssertEqual(vm.holeNumber, 1, "без снимка навигация не двигается")
    }

    // MARK: - addShot() кладёт удар в WatchShotQueue

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

    /// Регрессия структурной гарантии: раньше плейсхолдеры "сеялись" в
    /// локальный кэш и приходилось следить, чтобы они не утекли в очередь.
    /// Теперь сеять НЕЧЕГО и НЕЧЕМ — очередь пуста, пока игрок сам не
    /// нажмёт "+", независимо от того, сколько ударов уже на сервере.
    func testServerConfirmedShotsNeverAppearInTheQueue() {
        let queue = makeQueue()
        let holes = [WatchHole(number: 4, par: 5, distanceMeters: 480, myShots: 3)]
        let vm = WatchRoundViewModel(
            snapshot: makeSnapshot(roundId: "round-1", totalHoles: 4, holes: holes, clubs: ["Driver", "3 Wood"], activeHoleNumber: 4),
            shotQueue: queue
        )
        XCTAssertTrue(queue.pending.isEmpty, "появление снимка с myShots > 0 ничего не кладёт в очередь")

        vm.selectedClub = "3 Wood"
        vm.addShot()

        XCTAssertEqual(queue.pending.count, 1)
        XCTAssertEqual(queue.pending.first?.clubs, ["3 Wood"], "только реально введённый на часах удар")
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

    func testRemoveShotDownToEmptyClearsQueueSlot() {
        let queue = makeQueue()
        let holes = [WatchHole(number: 1, par: 4, distanceMeters: 300, myShots: 1)]
        let vm = WatchRoundViewModel(
            snapshot: makeSnapshot(roundId: "round-1", totalHoles: 1, holes: holes, activeHoleNumber: 1),
            shotQueue: queue
        )
        vm.addShot()
        XCTAssertEqual(queue.pending.first?.clubs, ["Driver"])

        vm.removeShot()  // убираем ровно тот удар, что сами добавили

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
        let vm = WatchRoundViewModel(snapshot: snapshot, shotQueue: makeQueue())
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
        let vm = WatchRoundViewModel(snapshot: snapshot, shotQueue: makeQueue())
        XCTAssertNil(vm.greenDistanceMeters)
    }

    func testGreenDistanceNilWhenAccuracyPoor() {
        let holes = [WatchHole(number: 3, par: 4, distanceMeters: 300, myShots: 0)]
        let snapshot = WatchRoundSnapshot(
            roundId: "round-1", courseName: "Test", totalHoles: 4, holes: holes,
            clubs: ["Driver"], greens: [3: GreenMark(lat: 55.700000, lng: 37.400000)],
            activeHoleNumber: 3, units: .m, updatedAt: Date()
        )
        let vm = WatchRoundViewModel(snapshot: snapshot, shotQueue: makeQueue())
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
        let vm = WatchRoundViewModel(snapshot: snapshot, shotQueue: makeQueue())
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
        let vm = WatchRoundViewModel(snapshot: snapshot, shotQueue: makeQueue())
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
        let vm = WatchRoundViewModel(snapshot: snapshot, shotQueue: makeQueue())
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
        let vm = WatchRoundViewModel(snapshot: snapshot, shotQueue: makeQueue())
        vm.currentFix = GeoFix(lat: 55.700000, lng: 37.400000, accuracy: 5, timestamp: Date())

        let distanceHole3 = vm.greenDistanceMeters
        XCTAssertEqual(Double(distanceHole3 ?? 0), 111, accuracy: 3)

        vm.nextHole()
        XCTAssertEqual(vm.holeNumber, 4)
        let distanceHole4 = vm.greenDistanceMeters
        XCTAssertEqual(Double(distanceHole4 ?? 0), 222, accuracy: 3)
        XCTAssertNotEqual(distanceHole3, distanceHole4, "смена лунки меняет дистанцию до грина")
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

    // MARK: - Новая модель (живое ревью Task 4, пятый раунд правок):
    // границу "confirmedCount vs myShots" убрали целиком. Ниже — трассы,
    // которые эта граница ломала, и требуемое ревью поведение.

    /// Трасса 1: удар застрял в очереди часов (телефон вне связи), затем
    /// игрок делает 2 удара НА ТЕЛЕФОНЕ той же лунки — снимок обгоняет
    /// квитанцию с myShots: 2. Следующий addShot() на часах ОБЯЗАН попасть
    /// в очередь — старая формула confirmedCount = max(myShots, durable)
    /// делала unsyncedShots пустым, и addShot() молча становился no-op'ом.
    func testAddShotAlwaysQueuesEvenWhenSnapshotMyShotsGrew() {
        let queue = makeQueue()
        queue.enqueue(roundId: "round-1", holeNumber: 1, clubs: ["Driver"])  // застрял в очереди

        let holes = [WatchHole(number: 1, par: 4, distanceMeters: 300, myShots: 2)]
        let vm = WatchRoundViewModel(
            snapshot: makeSnapshot(roundId: "round-1", totalHoles: 1, holes: holes, clubs: ["Driver", "Putter"], activeHoleNumber: 1),
            shotQueue: queue
        )
        XCTAssertEqual(vm.shotCount, 3, "2 сервер + 1 в очереди на часах")

        vm.selectedClub = "Putter"
        vm.addShot()

        XCTAssertEqual(vm.pendingClubs, ["Driver", "Putter"], "новый удар ОБЯЗАН попасть в очередь — addShot() никогда не no-op")
        XCTAssertEqual(queue.pending.first { $0.holeNumber == 1 }?.clubs, ["Driver", "Putter"])
        XCTAssertEqual(vm.shotCount, 4, "2 сервер + 2 в очереди")
    }

    /// Трасса 2: параллельный ввод — 2 удара уже подтверждены сервером
    /// (телефон), 1 удар введён на часах и ждёт квитанции. Отображаемый
    /// счёт не должен ни задваивать, ни терять ни один из трёх. Реальное
    /// отсутствие дубля НА СЕРВЕРЕ при мердже покрыто отдельно —
    /// WatchBridgeTests (Fix 1, baseState берёт pendingShot/серверный
    /// раунд как базу и дописывает хвост часов).
    func testParallelInputPhoneAndWatchDoNotDoubleCountInDisplay() {
        let queue = makeQueue()
        queue.enqueue(roundId: "round-1", holeNumber: 1, clubs: ["Putter"])

        let holes = [WatchHole(number: 1, par: 4, distanceMeters: 300, myShots: 2)]
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(roundId: "round-1", totalHoles: 1, holes: holes, activeHoleNumber: 1), shotQueue: queue)

        XCTAssertEqual(vm.shotCount, 3, "2 с телефона + 1 с часов = 3, не 2 и не 4")
    }

    /// Трасса 3 (регрессия Fix 7): удар застрял в очереди на часах,
    /// приложение часов "выгружено" — здесь это буквально пересоздание
    /// VM, поскольку никакого in-memory кэша, который мог бы разойтись с
    /// диском, больше не существует.
    func testUnconfirmedShotSurvivesSimulatedRestart() {
        let queue = makeQueue()
        queue.enqueue(roundId: "round-1", holeNumber: 5, clubs: ["Driver"])

        let holes = [WatchHole(number: 5, par: 4, distanceMeters: 300, myShots: 0)]
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(roundId: "round-1", totalHoles: 5, holes: holes, activeHoleNumber: 5), shotQueue: queue)

        XCTAssertEqual(vm.pendingClubs, ["Driver"], "неподтверждённый удар виден сразу после пересоздания VM")
        XCTAssertEqual(vm.shotCount, 1)

        // И он реально уходит — не застрял в никуда: следующий addShot()
        // растит тот же durable-хвост.
        vm.addShot()
        XCTAssertEqual(queue.pending.first { $0.holeNumber == 5 }?.clubs.count, 2)
    }

    /// Трасса 4а: снимок обгоняет квитанцию — ОСОЗНАННЫЙ временный
    /// компромисс (см. заголовок WatchRoundViewModel.swift): счёт на
    /// экране кратковременно завышен (удар учтён и в myShots, и в ещё не
    /// срезанном хвосте), пока квитанция не срежет хвост. Явно фиксируем
    /// это ожидание тестом, а не спрятанным допущением.
    func testTemporaryOvercountWindowWhenSnapshotArrivesBeforeReceiptTrimsQueue() {
        let queue = makeQueue()
        queue.enqueue(roundId: "round-1", holeNumber: 1, clubs: ["Driver"])

        let holes = [WatchHole(number: 1, par: 4, distanceMeters: 300, myShots: 1)]
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(roundId: "round-1", totalHoles: 1, holes: holes, activeHoleNumber: 1), shotQueue: queue)
        XCTAssertEqual(vm.shotCount, 2, "временное завышение — тот же удар учтён и в myShots, и в хвосте")

        queue.markConfirmed(roundId: "round-1", holeNumber: 1, acceptedCount: 1)

        XCTAssertEqual(vm.shotCount, 1, "квитанция срезала хвост — окно закрылось, счёт снова верный")
    }

    /// Трасса 4б: обратный порядок — квитанция обгоняет снимок. Хвост уже
    /// срезан к моменту, когда снимок наконец догоняет — задвоения не
    /// возникает вовсе (окно из 4а даже не открывается).
    func testNoOvercountWhenReceiptProcessedBeforeSnapshotCatchesUp() {
        let queue = makeQueue()
        queue.enqueue(roundId: "round-1", holeNumber: 1, clubs: ["Driver"])
        queue.markConfirmed(roundId: "round-1", holeNumber: 1, acceptedCount: 1)

        let holes = [WatchHole(number: 1, par: 4, distanceMeters: 300, myShots: 1)]
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(roundId: "round-1", totalHoles: 1, holes: holes, activeHoleNumber: 1), shotQueue: queue)

        XCTAssertEqual(vm.shotCount, 1, "квитанция обогнала снимок — задвоения нет вовсе")
    }

    /// Трасса 5: removeShot() при пустом локальном хвосте — удар уже
    /// записан на сервере, с часов его снять нельзя. По построению не
    /// трогает серверные удары (нет отдельной защиты вида allowClear —
    /// removeShot() физически не может тронуть ничего, кроме
    /// shotQueue.pending).
    func testRemoveShotDoesNothingWhenLocalTailIsEmpty() {
        let queue = makeQueue()
        let holes = [WatchHole(number: 1, par: 4, distanceMeters: 300, myShots: 3)]
        let vm = WatchRoundViewModel(snapshot: makeSnapshot(roundId: "round-1", totalHoles: 1, holes: holes, activeHoleNumber: 1), shotQueue: queue)
        XCTAssertEqual(vm.shotCount, 3)

        vm.removeShot()

        XCTAssertEqual(vm.shotCount, 3, "removeShot не может снять серверный удар с часов")
        XCTAssertTrue(queue.pending.isEmpty)
    }
}
