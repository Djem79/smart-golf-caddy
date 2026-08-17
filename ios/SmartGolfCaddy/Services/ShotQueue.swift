// ios/SmartGolfCaddy/Services/ShotQueue.swift
// Порт src/services/shotQueue.ts. Удары НИКОГДА не шлём напрямую —
// только через recordShotQueued: сначала durable-запись в файл, потом
// попытка отправки. Безопасно, т.к. recordShot идемпотентна (пишет весь
// массив clubs слота) — очереди достаточно последнего состояния на слот
// (last-write-wins).
import FirebaseFunctions
import Foundation
import Network

struct PendingShot: Codable, Equatable {
    var roundId: String
    var holeIndex: Int
    var targetUid: String
    var clubs: [String]
    var updatedAt: TimeInterval
}

enum RecordOutcome {
    case synced
    case queued
    case rejected(Error)
}

extension Notification.Name {
    static let shotQueueDidChange = Notification.Name("shotQueueDidChange")
}

final class ShotQueue: @unchecked Sendable {

    static let shared = ShotQueue(
        storeURL: ShotQueue.defaultStoreURL(),
        sender: { shot in
            try await RoundsService.recordShot(
                roundId: shot.roundId, holeIndex: shot.holeIndex,
                targetUid: shot.targetUid, clubs: shot.clubs
            )
        },
        isOnline: { ShotQueue.pathMonitorOnline }
    )

    // Ошибки сервера, которые не исправятся повтором — дроп из очереди.
    private static let permanentCodes: Set<FunctionsErrorCode> = [
        .permissionDenied, .unauthenticated, .failedPrecondition,
        .invalidArgument, .notFound,
    ]

    private let storeURL: URL
    private let sender: (PendingShot) async throws -> Void
    private let isOnline: () -> Bool
    private let ioQueue = DispatchQueue(label: "sgc.shotqueue.io")
    private var flushing = false

    init(storeURL: URL,
         sender: @escaping (PendingShot) async throws -> Void,
         isOnline: @escaping () -> Bool) {
        self.storeURL = storeURL
        self.sender = sender
        self.isOnline = isOnline
    }

    // MARK: хранилище (JSON-файл, ключ слота "round:hole:uid")

    private func slotKey(_ roundId: String, _ holeIndex: Int, _ targetUid: String) -> String {
        "\(roundId):\(holeIndex):\(targetUid)"
    }

    private func load() -> [String: PendingShot] {
        ioQueue.sync {
            guard let data = try? Data(contentsOf: storeURL) else { return [:] }
            return (try? JSONDecoder().decode([String: PendingShot].self, from: data)) ?? [:]
        }
    }

    private func persist(_ map: [String: PendingShot]) {
        ioQueue.sync {
            if let data = try? JSONEncoder().encode(map) {
                try? data.write(to: storeURL, options: .atomic)
            }
        }
        NotificationCenter.default.post(name: .shotQueueDidChange, object: nil)
    }

    // MARK: публичный интерфейс

    func pendingShot(roundId: String, holeIndex: Int, targetUid: String) -> PendingShot? {
        load()[slotKey(roundId, holeIndex, targetUid)]
    }

    func pendingCount(roundId: String) -> Int {
        load().values.filter { $0.roundId == roundId }.count
    }

    func recordShotQueued(roundId: String, holeIndex: Int, targetUid: String, clubs: [String]) async -> RecordOutcome {
        let entry = PendingShot(roundId: roundId, holeIndex: holeIndex,
                                targetUid: targetUid, clubs: clubs,
                                updatedAt: Date().timeIntervalSince1970)
        var map = load()
        map[slotKey(roundId, holeIndex, targetUid)] = entry
        persist(map)

        guard isOnline() else { return .queued }

        do {
            try await sender(entry)
            dequeueIfMatches(entry)
            return .synced
        } catch {
            if Self.isPermanent(error) {
                dequeueIfMatches(entry)
                return .rejected(error)
            }
            return .queued
        }
    }

    /// Снять слот, только если в очереди всё ещё ровно то, что мы отправили —
    /// не затирает более новый удар, записанный пока шла отправка.
    private func dequeueIfMatches(_ entry: PendingShot) {
        var map = load()
        let key = slotKey(entry.roundId, entry.holeIndex, entry.targetUid)
        if let current = map[key], current.clubs == entry.clubs {
            map.removeValue(forKey: key)
            persist(map)
        }
    }

    @discardableResult
    func flush() async -> Int {
        if flushing { return load().count }
        flushing = true
        defer { flushing = false }

        for (key, entry) in load() {
            do {
                try await sender(entry)
                var current = load()
                if let live = current[key], live.updatedAt == entry.updatedAt {
                    current.removeValue(forKey: key)
                    persist(current)
                }
            } catch {
                if Self.isPermanent(error) {
                    var current = load()
                    if let live = current[key], live.updatedAt == entry.updatedAt {
                        current.removeValue(forKey: key)
                        persist(current)
                    }
                    continue  // дроп и дальше
                }
                break  // transient — стоп до следующего online-события
            }
        }
        return load().count
    }

    // MARK: сеть и автозапуск

    private static var monitor: NWPathMonitor?
    private static var pathMonitorOnline = true

    func initSync() {
        guard Self.monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let wasOffline = !Self.pathMonitorOnline
            Self.pathMonitorOnline = online
            if online && wasOffline {
                Task { await self?.flush() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "sgc.shotqueue.network"))
        Self.monitor = monitor
        Task { await flush() }
    }

    private static func isPermanent(_ error: Error) -> Bool {
        let ns = error as NSError
        // Боевой путь: NSError от FirebaseFunctions c FunctionsErrorDomain.
        if ns.domain == FunctionsErrorDomain,
           let code = FunctionsErrorCode(rawValue: ns.code) {
            return permanentCodes.contains(code)
        }
        // Тестовый/переносимый путь: домен functions + строковый код.
        if let raw = ns.userInfo["FIRFunctionsErrorCode"] as? String {
            let mapped: [String: FunctionsErrorCode] = [
                "permission-denied": .permissionDenied,
                "unauthenticated": .unauthenticated,
                "failed-precondition": .failedPrecondition,
                "invalid-argument": .invalidArgument,
                "not-found": .notFound,
                "unavailable": .unavailable,
            ]
            if let code = mapped[raw] { return permanentCodes.contains(code) }
        }
        return false
    }

    private static func defaultStoreURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pending-shots-v1.json")
    }
}
