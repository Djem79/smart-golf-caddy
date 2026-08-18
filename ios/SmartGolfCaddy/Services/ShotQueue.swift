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
    // Optional — старые файлы очереди (записанные до Task 3) не содержат
    // это поле; декодер синтезирует nil без миграции. На использование —
    // `shot.distances ?? []`.
    var distances: [Int]?
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
            // БЕЗ `?? []` — legacy-запись (nil) должна остаться nil: пустой
            // массив при непустых clubs бьётся о серверный Zod-refine
            // (distances.length == clubs.length) → invalid-argument →
            // permanent → удар теряется. nil → ключ выпадает из payload,
            // сервер сохраняет прежние distances.
            try await RoundsService.recordShot(
                roundId: shot.roundId, holeIndex: shot.holeIndex,
                targetUid: shot.targetUid, clubs: shot.clubs,
                distances: shot.distances
            )
        }
    )

    // Ошибки сервера, которые не исправятся повтором — дроп из очереди.
    private static let permanentCodes: Set<FunctionsErrorCode> = [
        .permissionDenied, .unauthenticated, .failedPrecondition,
        .invalidArgument, .notFound,
    ]

    private let storeURL: URL
    private let sender: (PendingShot) async throws -> Void
    // Тестовый инжект оверрайда online-статуса; в shared — nil, реальный
    // статус читается из инстансного поля `online`, обновляемого монитором.
    private let isOnlineOverride: (() -> Bool)?
    private let ioQueue = DispatchQueue(label: "sgc.shotqueue.io")
    private var flushing = false
    private var monitor: NWPathMonitor?
    private var online = true

    init(storeURL: URL,
         sender: @escaping (PendingShot) async throws -> Void,
         isOnline: (() -> Bool)? = nil) {
        self.storeURL = storeURL
        self.sender = sender
        self.isOnlineOverride = isOnline
    }

    // MARK: хранилище (JSON-файл, ключ слота "round:hole:uid")

    private func slotKey(_ roundId: String, _ holeIndex: Int, _ targetUid: String) -> String {
        "\(roundId):\(holeIndex):\(targetUid)"
    }

    /// Тела load/persist БЕЗ синхронизации — вызывать только изнутри
    /// ioQueue.sync (напрямую или через withMap).
    private func loadLocked() -> [String: PendingShot] {
        guard let data = try? Data(contentsOf: storeURL) else { return [:] }
        return (try? JSONDecoder().decode([String: PendingShot].self, from: data)) ?? [:]
    }

    private func persistLocked(_ map: [String: PendingShot]) {
        if let data = try? JSONEncoder().encode(map) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    /// Атомарно: load → мутация → persist (одна ioQueue.sync — read-modify-write
    /// без гонки между конкурентными вызовами). Возвращает флаг «мапа
    /// изменилась» — нотификация постится ВНЕ sync-блока (deadlock-гигиена).
    @discardableResult
    private func withMap<T>(_ mutate: (inout [String: PendingShot]) -> T) -> T {
        var changed = false
        let result: T = ioQueue.sync {
            var map = loadLocked()
            let before = map
            let value = mutate(&map)
            if map != before {
                persistLocked(map)
                changed = true
            }
            return value
        }
        if changed {
            NotificationCenter.default.post(name: .shotQueueDidChange, object: nil)
        }
        return result
    }

    // MARK: публичный интерфейс

    func pendingShot(roundId: String, holeIndex: Int, targetUid: String) -> PendingShot? {
        ioQueue.sync { loadLocked() }[slotKey(roundId, holeIndex, targetUid)]
    }

    func pendingCount(roundId: String) -> Int {
        ioQueue.sync { loadLocked() }.values.filter { $0.roundId == roundId }.count
    }

    func recordShotQueued(roundId: String, holeIndex: Int, targetUid: String, clubs: [String], distances: [Int]) async -> RecordOutcome {
        let entry = PendingShot(roundId: roundId, holeIndex: holeIndex,
                                targetUid: targetUid, clubs: clubs, distances: distances,
                                updatedAt: Date().timeIntervalSince1970)
        let key = slotKey(roundId, holeIndex, targetUid)
        withMap { map in map[key] = entry }

        let isOnline = isOnlineOverride?() ?? online
        guard isOnline else { return .queued }

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
    /// не затирает более новый удар, записанный пока шла отправка. Сверка
    /// clubs и удаление — внутри одной атомарной мутации.
    private func dequeueIfMatches(_ entry: PendingShot) {
        let key = slotKey(entry.roundId, entry.holeIndex, entry.targetUid)
        withMap { map in
            if let current = map[key], current.clubs == entry.clubs,
               (current.distances ?? []) == (entry.distances ?? []) {
                map.removeValue(forKey: key)
            }
        }
    }

    private func tryBeginFlush() -> Bool {
        ioQueue.sync {
            if flushing { return false }
            flushing = true
            return true
        }
    }

    private func endFlush() {
        ioQueue.sync { flushing = false }
    }

    @discardableResult
    func flush() async -> Int {
        guard tryBeginFlush() else { return ioQueue.sync { loadLocked() }.count }
        defer { endFlush() }

        // Снапшот берём один раз под lock; отправка идёт БЕЗ lock — нельзя
        // держать ioQueue во время await.
        let snapshot = ioQueue.sync { loadLocked() }
        for (key, entry) in snapshot {
            do {
                try await sender(entry)
                withMap { map in
                    if let live = map[key], live.updatedAt == entry.updatedAt {
                        map.removeValue(forKey: key)
                    }
                }
            } catch {
                if Self.isPermanent(error) {
                    withMap { map in
                        if let live = map[key], live.updatedAt == entry.updatedAt {
                            map.removeValue(forKey: key)
                        }
                    }
                    continue  // дроп и дальше
                }
                break  // transient — стоп до следующего online-события
            }
        }
        return ioQueue.sync { loadLocked() }.count
    }

    // MARK: сеть и автозапуск

    func initSync() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let isOnline = path.status == .satisfied
            let wasOffline = !self.online
            self.online = isOnline
            if isOnline && wasOffline {
                Task { await self.flush() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "sgc.shotqueue.network"))
        self.monitor = monitor
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
