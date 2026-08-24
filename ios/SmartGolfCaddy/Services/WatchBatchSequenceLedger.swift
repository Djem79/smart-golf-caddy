// ios/SmartGolfCaddy/Services/WatchBatchSequenceLedger.swift
// Durable-журнал "последний применённый sequence" на слот
// round:holeIndex:uid (Fix 5, живое ревью Task 4) — телефон отличает
// повторную доставку ТОГО ЖЕ батча с часов (тот же sequence — применение
// пропустить, но квитанцию всё равно отправить) от новой попытки
// (sequence больше — применить). Suffix-эвристика по содержимому клюшек
// (первая версия Fix 4) не годилась: она путала "этот батч уже применён"
// с "игрок ударил той же клюшкой ещё раз" (например, второй патт подряд
// на том же грине) и молча теряла повторный удар — см. живое ревью.
//
// Тот же стиль, что и ShotQueue/WatchShotQueue: JSON-файл в Application
// Support, атомарная запись под ioQueue.sync.
import Foundation

final class WatchBatchSequenceLedger: @unchecked Sendable {
    static let shared = WatchBatchSequenceLedger(storeURL: WatchBatchSequenceLedger.defaultStoreURL())

    private let storeURL: URL
    private let ioQueue = DispatchQueue(label: "sgc.watchbatchsequence.io")

    init(storeURL: URL) {
        self.storeURL = storeURL
    }

    private func slotKey(_ roundId: String, _ holeIndex: Int, _ uid: String) -> String {
        "\(roundId):\(holeIndex):\(uid)"
    }

    private func loadLocked() -> [String: Int] {
        guard let data = try? Data(contentsOf: storeURL) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    private func persistLocked(_ map: [String: Int]) {
        if let data = try? JSONEncoder().encode(map) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    /// nil = для этого слота ещё ничего не применялось (или журнал
    /// пуст — свежая установка).
    func lastApplied(roundId: String, holeIndex: Int, uid: String) -> Int? {
        ioQueue.sync { loadLocked()[slotKey(roundId, holeIndex, uid)] }
    }

    /// Записывает sequence как применённый. Монотонно — не понижает уже
    /// записанное значение (защита от гипотетической доставки не по
    /// порядку — младший sequence, пришедший позже, не должен откатить
    /// журнал назад и заставить телефон повторно применить старый батч).
    func recordApplied(roundId: String, holeIndex: Int, uid: String, sequence: Int) {
        ioQueue.sync {
            let key = slotKey(roundId, holeIndex, uid)
            var map = loadLocked()
            guard sequence > (map[key] ?? 0) else { return }
            map[key] = sequence
            persistLocked(map)
        }
    }

    private static func defaultStoreURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("watch-batch-sequence-v1.json")
    }
}
