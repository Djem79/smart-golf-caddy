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
        let outcome = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u", clubs: ["Driver"])
        guard case .synced = outcome else { return XCTFail("ожидали synced") }
        XCTAssertNil(queue.pendingShot(roundId: "r", holeIndex: 0, targetUid: "u"))
        XCTAssertEqual(queue.pendingCount(roundId: "r"), 0)
    }

    func testOfflineStaysQueuedAndSurvivesReload() async {
        let queue = makeQueue(online: { false })
        let outcome = await queue.recordShotQueued(roundId: "r", holeIndex: 2, targetUid: "u", clubs: ["7i", "Putter"])
        guard case .queued = outcome else { return XCTFail("ожидали queued") }
        XCTAssertEqual(queue.pendingShot(roundId: "r", holeIndex: 2, targetUid: "u")?.clubs, ["7i", "Putter"])
        // «Перезапуск»: новый инстанс над тем же файлом
        let reloaded = makeQueue(online: { false })
        XCTAssertEqual(reloaded.pendingShot(roundId: "r", holeIndex: 2, targetUid: "u")?.clubs, ["7i", "Putter"])
        XCTAssertEqual(reloaded.pendingCount(roundId: "r"), 1)
    }

    func testLastWriteWinsPerSlot() async {
        let queue = makeQueue(online: { false })
        _ = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u", clubs: ["Driver"])
        _ = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u", clubs: ["Driver", "PW"])
        XCTAssertEqual(queue.pendingShot(roundId: "r", holeIndex: 0, targetUid: "u")?.clubs, ["Driver", "PW"])
        XCTAssertEqual(queue.pendingCount(roundId: "r"), 1)
    }

    func testTransientFailureStaysQueued() async {
        let queue = makeQueue(sender: { _ in
            throw NSError(domain: "com.firebase.functions", code: 14,
                          userInfo: ["FIRFunctionsErrorCode": "unavailable"])
        })
        let outcome = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u", clubs: ["Driver"])
        guard case .queued = outcome else { return XCTFail("ожидали queued") }
        XCTAssertNotNil(queue.pendingShot(roundId: "r", holeIndex: 0, targetUid: "u"))
    }

    func testPermanentFailureDropsAndReports() async {
        let queue = makeQueue(sender: { _ in throw self.permanentError() })
        let outcome = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u", clubs: ["Driver"])
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
        _ = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u", clubs: ["Driver"])
        _ = await queue.recordShotQueued(roundId: "r", holeIndex: 1, targetUid: "u", clubs: ["7i"])
        XCTAssertEqual(queue.pendingCount(roundId: "r"), 2)

        let remaining = await queue.flush()
        XCTAssertEqual(remaining, 0)
        XCTAssertEqual(sent.count, 2)

        _ = await queue.recordShotQueued(roundId: "r", holeIndex: 2, targetUid: "u", clubs: ["PW"])
        failNext = true
        let remaining2 = await queue.flush()
        XCTAssertEqual(remaining2, 1)  // transient — остался в очереди
    }

    func testFlushDropsPermanent() async {
        let queue = makeQueue(sender: { _ in throw self.permanentError() }, online: { false })
        _ = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u", clubs: ["Driver"])
        let remaining = await queue.flush()
        XCTAssertEqual(remaining, 0)  // permanent дропнут, очередь не заклинена
    }

    func testConcurrentEnqueuesDoNotLoseEntries() async {
        let queue = makeQueue(online: { false })
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    _ = await queue.recordShotQueued(roundId: "r", holeIndex: i, targetUid: "u", clubs: ["7i"])
                }
            }
        }
        XCTAssertEqual(queue.pendingCount(roundId: "r"), 20)
    }
}
