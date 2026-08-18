import XCTest
@testable import SmartGolfCaddy

final class ShotQueueTests: XCTestCase {
    private var storeURL: URL!

    override func setUp() {
        super.setUp()
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shotqueue-test-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeURL)
        super.tearDown()
    }

    private func makeQueue(
        sender: @escaping (PendingShot) async throws -> Void = { _ in },
        online: @escaping () -> Bool = { true }
    ) -> ShotQueue {
        ShotQueue(storeURL: storeURL, sender: sender, isOnline: online)
    }

    private func permanentError() -> NSError {
        NSError(domain: "com.firebase.functions", code: 7,
                userInfo: ["FIRFunctionsErrorCode": "permission-denied"])
    }

    func testSyncedPathClearsQueue() async {
        let queue = makeQueue()
        let outcome = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u", clubs: ["Driver"], distances: [])
        guard case .synced = outcome else { return XCTFail("ожидали synced") }
        XCTAssertNil(queue.pendingShot(roundId: "r", holeIndex: 0, targetUid: "u"))
        XCTAssertEqual(queue.pendingCount(roundId: "r"), 0)
    }

    func testOfflineStaysQueuedAndSurvivesReload() async {
        let queue = makeQueue(online: { false })
        let outcome = await queue.recordShotQueued(roundId: "r", holeIndex: 2, targetUid: "u", clubs: ["7i", "Putter"], distances: [])
        guard case .queued = outcome else { return XCTFail("ожидали queued") }
        XCTAssertEqual(queue.pendingShot(roundId: "r", holeIndex: 2, targetUid: "u")?.clubs, ["7i", "Putter"])
        // «Перезапуск»: новый инстанс над тем же файлом
        let reloaded = makeQueue(online: { false })
        XCTAssertEqual(reloaded.pendingShot(roundId: "r", holeIndex: 2, targetUid: "u")?.clubs, ["7i", "Putter"])
        XCTAssertEqual(reloaded.pendingCount(roundId: "r"), 1)
    }

    func testLastWriteWinsPerSlot() async {
        let queue = makeQueue(online: { false })
        _ = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u", clubs: ["Driver"], distances: [])
        _ = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u", clubs: ["Driver", "PW"], distances: [0, 0])
        XCTAssertEqual(queue.pendingShot(roundId: "r", holeIndex: 0, targetUid: "u")?.clubs, ["Driver", "PW"])
        XCTAssertEqual(queue.pendingCount(roundId: "r"), 1)
    }

    func testTransientFailureStaysQueued() async {
        let queue = makeQueue(sender: { _ in
            throw NSError(domain: "com.firebase.functions", code: 14,
                          userInfo: ["FIRFunctionsErrorCode": "unavailable"])
        })
        let outcome = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u", clubs: ["Driver"], distances: [])
        guard case .queued = outcome else { return XCTFail("ожидали queued") }
        XCTAssertNotNil(queue.pendingShot(roundId: "r", holeIndex: 0, targetUid: "u"))
    }

    func testPermanentFailureDropsAndReports() async {
        let queue = makeQueue(sender: { _ in throw self.permanentError() })
        let outcome = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u", clubs: ["Driver"], distances: [])
        guard case .rejected = outcome else { return XCTFail("ожидали rejected") }
        XCTAssertNil(queue.pendingShot(roundId: "r", holeIndex: 0, targetUid: "u"))
    }

    func testFlushSendsAllAndStopsOnTransient() async {
        var sent: [String] = []
        var failNext = false
        let queue = makeQueue(sender: { shot in
            if failNext {
                throw NSError(domain: "com.firebase.functions", code: 14,
                              userInfo: ["FIRFunctionsErrorCode": "unavailable"])
            }
            sent.append("\(shot.roundId):\(shot.holeIndex)")
        }, online: { false })
        _ = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u", clubs: ["Driver"], distances: [])
        _ = await queue.recordShotQueued(roundId: "r", holeIndex: 1, targetUid: "u", clubs: ["7i"], distances: [])
        XCTAssertEqual(queue.pendingCount(roundId: "r"), 2)

        let remaining = await queue.flush()
        XCTAssertEqual(remaining, 0)
        XCTAssertEqual(sent.count, 2)

        _ = await queue.recordShotQueued(roundId: "r", holeIndex: 2, targetUid: "u", clubs: ["PW"], distances: [])
        failNext = true
        let remaining2 = await queue.flush()
        XCTAssertEqual(remaining2, 1)  // transient — остался в очереди
    }

    func testFlushDropsPermanent() async {
        let queue = makeQueue(sender: { _ in throw self.permanentError() }, online: { false })
        _ = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u", clubs: ["Driver"], distances: [])
        let remaining = await queue.flush()
        XCTAssertEqual(remaining, 0)  // permanent дропнут, очередь не заклинена
    }

    func testConcurrentEnqueuesDoNotLoseEntries() async {
        let queue = makeQueue(online: { false })
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    _ = await queue.recordShotQueued(roundId: "r", holeIndex: i, targetUid: "u", clubs: ["7i"], distances: [])
                }
            }
        }
        XCTAssertEqual(queue.pendingCount(roundId: "r"), 20)
    }

    func testQueuePreservesDistances() async {
        let queue = makeQueue(online: { false })
        _ = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u",
                                         clubs: ["Driver", "7i"], distances: [215, 0])
        XCTAssertEqual(queue.pendingShot(roundId: "r", holeIndex: 0, targetUid: "u")?.distances, [215, 0])
    }

    /// Legacy-запись (до Task 3) на диске не содержит ключа "distances" —
    /// декодер синтезирует nil. Sender должен получить nil, а НЕ [] —
    /// иначе сервер видит непустые clubs + пустой distances и бьётся о
    /// Zod-refine (length mismatch) → invalid-argument → удар дропается.
    func testLegacyEntryWithNilDistancesSendsNilNotEmptyArray() async {
        let legacyJSON = """
        {"r:0:u":{"roundId":"r","holeIndex":0,"targetUid":"u","clubs":["Driver"],"updatedAt":0}}
        """
        try? legacyJSON.data(using: .utf8)!.write(to: storeURL)

        var senderCalled = false
        var receivedDistances: [Int]? = [999]  // sentinel, отличный и от nil, и от []
        let queue = makeQueue(sender: { shot in
            senderCalled = true
            receivedDistances = shot.distances
        })
        let remaining = await queue.flush()

        XCTAssertTrue(senderCalled)
        XCTAssertNil(receivedDistances)
        XCTAssertEqual(remaining, 0)
    }

    /// dequeueIfMatches должен сверять И clubs, И distances: пока старый
    /// удар «летит» к серверу, новый замер той же лунки может переписать
    /// слот теми же clubs, но другой distances — такой новый замер не
    /// должен быть стёрт возвратом старого.
    func testDequeueIfMatchesRespectsDistancesNotJustClubs() async {
        var onlineFlag = true
        let queue = makeQueue(
            sender: { shot in
                if shot.distances == [0] {
                    // Имитируем «полёт» A — держим его в sender, пока тест
                    // не перезапишет слот B.
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            },
            online: { onlineFlag }
        )

        let flightTask = Task {
            _ = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u",
                                             clubs: ["Driver"], distances: [0])
        }
        // Дать A время уйти в sender и записать слот.
        try? await Task.sleep(nanoseconds: 20_000_000)
        onlineFlag = false  // B должен только перезаписать слот, не улететь в sender
        _ = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u",
                                         clubs: ["Driver"], distances: [215])

        await flightTask.value  // дождаться, что A вернулась и отработала dequeueIfMatches

        XCTAssertEqual(queue.pendingShot(roundId: "r", holeIndex: 0, targetUid: "u")?.distances, [215])
    }
}
