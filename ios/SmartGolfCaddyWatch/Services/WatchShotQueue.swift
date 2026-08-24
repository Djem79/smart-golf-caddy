// ios/SmartGolfCaddyWatch/Services/WatchShotQueue.swift
// Durable-очередь ударов на часах (Task 4, Phase 3c). В том же духе, что и
// ShotQueue на телефоне (файл в Application Support, JSON-словарь, слот
// "roundId:holeNumber" — last-write-wins), но проще: часы не вызывают
// recordShot напрямую — они отправляют хвост неподтверждённых клюшек
// телефону через PhoneBridge.send(batch:), а телефон уже сам пишет через
// recordShot (см. WatchBridge.swift). Запись НЕ удаляется, пока телефон не
// подтвердит приём квитанцией (markConfirmed) — так удар не теряется, если
// часы отправили батч и тут же перезапустились/потеряли связь.
//
// import WatchConnectivity здесь ЗАПРЕЩЁН (см. CLAUDE.md) — канал передачи
// инжектируется в flush(via:) closure'ом, реализация которого (PhoneBridge)
// живёт в отдельном файле.
import Foundation

/// Один слот очереди: хвост клюшек лунки, ещё не подтверждённый телефоном.
struct PendingWatchShot: Codable, Equatable {
    var roundId: String
    var holeNumber: Int
    var clubs: [String]
    var updatedAt: TimeInterval
}

extension Notification.Name {
    static let watchShotQueueDidChange = Notification.Name("watchShotQueueDidChange")
}

final class WatchShotQueue: @unchecked Sendable {

    static let shared = WatchShotQueue(storeURL: WatchShotQueue.defaultStoreURL())

    /// Сколько ждать квитанции, прежде чем считать батч потерянным и
    /// разрешить flush() отправить слот повторно. Без таймаута слот,
    /// отправка которого молча не удалась (например, WCSession не
    /// поддерживается на этом устройстве), остался бы помеченным "в пути"
    /// навсегда и никогда не переотправился бы.
    ///
    /// ВАЖНО (принятый компромисс): таймаут открывает узкое окно, где
    /// оригинальная отправка ВСЁ ЖЕ доходит позже (например, после
    /// восстановления Bluetooth) одновременно с повторной — тогда телефон
    /// может дописать один и тот же хвост дважды. Это осознанный компромисс
    /// уровня MVP: WatchShotBatch (Task 3) не несёт идентификатор доставки,
    /// поэтому полная идемпотентность потребовала бы отдельного номера
    /// версии на слот и явного трекинга baseline на телефоне — сложность,
    /// непропорциональная риску (узкое окно, некритичные последствия —
    /// лишний удар в счёте, поправимо вручную). Обычный путь (одна отправка
    /// за раз на слот, dedup через withMap) дублей не создаёт.
    static let inFlightTimeout: TimeInterval = 30

    private let storeURL: URL
    private let ioQueue = DispatchQueue(label: "sgc.watchshotqueue.io")
    /// НЕ персистится: после перезапуска часов судьба предыдущей отправки
    /// неизвестна — разрешаем немедленный повтор при следующем flush(),
    /// это безопасно (markConfirmed всегда триммит по ТЕКУЩЕМУ содержимому
    /// слота, а не по тому, что было отправлено раньше).
    private var inFlightSince: [String: Date] = [:]

    init(storeURL: URL) {
        self.storeURL = storeURL
    }

    private func slotKey(_ roundId: String, _ holeNumber: Int) -> String {
        "\(roundId):\(holeNumber)"
    }

    // MARK: хранилище

    private func loadLocked() -> [String: PendingWatchShot] {
        guard let data = try? Data(contentsOf: storeURL) else { return [:] }
        return (try? JSONDecoder().decode([String: PendingWatchShot].self, from: data)) ?? [:]
    }

    private func persistLocked(_ map: [String: PendingWatchShot]) {
        if let data = try? JSONEncoder().encode(map) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    /// Атомарно: load → мутация → persist (одна ioQueue.sync). Уведомление
    /// постится ВНЕ sync-блока — та же deadlock-гигиена, что и в ShotQueue.
    @discardableResult
    private func withMap<T>(_ mutate: (inout [String: PendingWatchShot]) -> T) -> T {
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
            NotificationCenter.default.post(name: .watchShotQueueDidChange, object: nil)
        }
        return result
    }

    // MARK: публичный интерфейс

    /// Все ожидающие подтверждения записи — источник для «не синхронизировано»
    /// бейджа UI. Стабильный порядок (по номеру лунки) ради предсказуемых тестов.
    var pending: [PendingWatchShot] {
        ioQueue.sync { loadLocked() }.values.sorted { $0.holeNumber < $1.holeNumber }
    }

    /// Кладёт/перезаписывает хвост неподтверждённых ударов лунки. Вызывающая
    /// сторона (WatchRoundViewModel.addShot/removeShot) обязана передавать
    /// сюда ПОЛНЫЙ текущий unsyncedShots(forHole:) — заглушки seedIfNeeded
    /// НИКОГДА не входят в этот хвост (см. комментарий у unsyncedShots в
    /// WatchRoundViewModel), поэтому они физически не могут попасть сюда.
    /// Слот "roundId:holeNumber" — last-write-wins: повторный enqueue той же
    /// лунки перезаписывает значение, а не накапливает историю, поэтому
    /// повтор не плодит записи. Пустой хвост снимает слот целиком.
    func enqueue(roundId: String, holeNumber: Int, clubs: [String]) {
        let key = slotKey(roundId, holeNumber)
        guard !clubs.isEmpty else {
            withMap { $0.removeValue(forKey: key) }
            return
        }
        let entry = PendingWatchShot(roundId: roundId, holeNumber: holeNumber, clubs: clubs,
                                     updatedAt: Date().timeIntervalSince1970)
        withMap { $0[key] = entry }
    }

    /// Квитанция с телефона (WatchShotReceiptEntry.acceptedCount): сколько
    /// клюшек ИЗ ТЕКУЩЕГО хвоста этого слота телефон только что принял.
    /// Срезаем подтверждённый префикс; если пользователь успел добавить на
    /// часах ещё ударов, пока квитанция была в пути, остаток остаётся в
    /// очереди — уйдёт со следующим flush(). Снимает флаг "в пути" в любом
    /// случае, даже если сам слот уже был снят иначе (защита от утечки
    /// состояния throttle'а).
    func markConfirmed(roundId: String, holeNumber: Int, acceptedCount: Int) {
        let key = slotKey(roundId, holeNumber)
        ioQueue.sync { inFlightSince.removeValue(forKey: key) }
        guard acceptedCount > 0 else { return }
        withMap { map in
            guard let live = map[key] else { return }
            if acceptedCount >= live.clubs.count {
                map.removeValue(forKey: key)
            } else {
                var updated = live
                updated.clubs = Array(live.clubs.dropFirst(acceptedCount))
                map[key] = updated
            }
        }
    }

    /// Отправляет ожидающие хвосты одним батчем на roundId через переданный
    /// канал (в проде — PhoneBridge.send(batch:), инжектируемый closure —
    /// в тестах). НЕ удаляет записи — снять слот может только markConfirmed
    /// по квитанции.
    ///
    /// Слот, чья отправка уже "в пути" (недавно flush'нута, квитанция ещё
    /// не пришла), пропускается — иначе повторная отправка растущего хвоста
    /// ДО получения квитанции заставила бы телефон дважды дописать одни и
    /// те же клюшки поверх уже дописанных (recordShot на телефоне ДОПИСЫВАЕТ
    /// присланный хвост к уже известным клюшкам, а не сверяет по
    /// идентификатору удара — см. WatchBridge). inFlightTimeout размораживает
    /// слот, если квитанция так и не пришла.
    func flush(via send: (WatchShotBatch) -> Void) {
        let now = Date()
        let entries: [PendingWatchShot] = ioQueue.sync {
            loadLocked().values.filter { entry in
                let key = slotKey(entry.roundId, entry.holeNumber)
                guard let since = inFlightSince[key] else { return true }
                return now.timeIntervalSince(since) > Self.inFlightTimeout
            }
        }
        guard !entries.isEmpty else { return }

        let byRound = Dictionary(grouping: entries, by: \.roundId)
        for roundId in byRound.keys.sorted() {
            let roundEntries = (byRound[roundId] ?? []).sorted { $0.holeNumber < $1.holeNumber }
            let batchEntries = roundEntries.map {
                WatchShotEntry(holeNumber: $0.holeNumber, clubs: $0.clubs, recordedAt: Date(timeIntervalSince1970: $0.updatedAt))
            }
            ioQueue.sync {
                for entry in roundEntries {
                    inFlightSince[slotKey(entry.roundId, entry.holeNumber)] = now
                }
            }
            send(WatchShotBatch(roundId: roundId, entries: batchEntries))
        }
    }

    private static func defaultStoreURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("watch-pending-shots-v1.json")
    }
}
