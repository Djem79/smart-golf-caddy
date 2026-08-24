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
    /// Постится markConfirmed(..., accepted: false) — сервер ОКОНЧАТЕЛЬНО
    /// отклонил батч этой лунки (Fix 3, живое ревью Task 4). userInfo:
    /// ["roundId": String, "holeNumber": Int]. WatchRoundViewModel слушает
    /// это, чтобы показать в UI "Не удалось синхронизировать" вместо
    /// бесконечного "не синхронизировано".
    static let watchShotSyncFailed = Notification.Name("watchShotSyncFailed")
}

final class WatchShotQueue: @unchecked Sendable {

    static let shared = WatchShotQueue(
        storeURL: WatchShotQueue.defaultStoreURL(name: "watch-pending-shots-v1.json"),
        confirmedStoreURL: WatchShotQueue.defaultStoreURL(name: "watch-confirmed-counts-v1.json")
    )

    /// Сколько ждать квитанции, прежде чем считать батч потерянным и
    /// разрешить flush() отправить слот повторно. Без таймаута слот,
    /// отправка которого молча не удалась (например, WCSession не
    /// поддерживается на этом устройстве), остался бы помеченным "в пути"
    /// навсегда и никогда не переотправился бы.
    ///
    /// ВАЖНО (принятый компромисс): таймаут открывает узкое окно, где
    /// оригинальная отправка ВСЁ ЖЕ доходит позже (например, после
    /// восстановления Bluetooth) одновременно с повторной. Живое ревью
    /// Task 4 закрыло основной риск этого окна на стороне телефона —
    /// WatchBridge.applyBatch теперь распознаёт "этот хвост уже дописан
    /// ровно таким же" (суффиксная проверка) и не дублирует повторно
    /// присланный батч. Остаётся не полностью идемпотентным только более
    /// экзотический случай (растущий хвост между двумя доставками одного
    /// поколения) — некритичные последствия (лишний удар в счёте),
    /// поправимо вручную.
    static let inFlightTimeout: TimeInterval = 30

    private let storeURL: URL
    private let confirmedStoreURL: URL
    private let ioQueue = DispatchQueue(label: "sgc.watchshotqueue.io")
    /// НЕ персистится: после перезапуска часов судьба предыдущей отправки
    /// неизвестна — разрешаем немедленный повтор при следующем flush(),
    /// это безопасно (markConfirmed всегда триммит по ТЕКУЩЕМУ содержимому
    /// слота, а не по тому, что было отправлено раньше).
    private var inFlightSince: [String: Date] = [:]

    init(storeURL: URL, confirmedStoreURL: URL) {
        self.storeURL = storeURL
        self.confirmedStoreURL = confirmedStoreURL
    }

    private func slotKey(_ roundId: String, _ holeNumber: Int) -> String {
        "\(roundId):\(holeNumber)"
    }

    // MARK: хранилище — хвосты на отправку

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

    // MARK: хранилище — монотонный счётчик подтверждённых ударов (Fix 2)

    /// Отдельный файл, отдельный от pending-хвостов: этот счётчик ТОЛЬКО
    /// растёт (markConfirmed прибавляет к нему), пока pending-хвост
    /// приходит и уходит. Источник истины для WatchRoundViewModel о том,
    /// сколько ударов лунки телефон уже принял — см. живое ревью Task 4,
    /// Fix 2: снимок с телефона (myShots) обновляется ТОЛЬКО когда там
    /// открыт экран лунки; при закрытом телефоне (обычная игра с часов на
    /// запястье) квитанция — единственный АКТУАЛЬНЫЙ сигнал.
    private func loadConfirmedLocked() -> [String: Int] {
        guard let data = try? Data(contentsOf: confirmedStoreURL) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    private func persistConfirmedLocked(_ map: [String: Int]) {
        if let data = try? JSONEncoder().encode(map) {
            try? data.write(to: confirmedStoreURL, options: .atomic)
        }
    }

    /// Сколько ударов данной лунки телефон уже подтвердил — используется
    /// WatchRoundViewModel как нижняя граница вместе со snapshot.myShots
    /// (`max` двух источников, см. её confirmedCount). ВКЛЮЧАЕТ
    /// seedConfirmedCountIfHigher-базу (см. ниже) — это НЕ просто сумма
    /// одних markConfirmed-приращений с нуля.
    func confirmedCount(roundId: String, holeNumber: Int) -> Int {
        ioQueue.sync { loadConfirmedLocked()[slotKey(roundId, holeNumber)] ?? 0 }
    }

    /// Поднимает счётчик до `count`, если он сейчас ниже — НЕ прибавляет.
    /// Вызывается WatchRoundViewModel.seedIfNeeded РОВНО ОДИН РАЗ на лунку
    /// (тем же условием, что сеет плейсхолдеры) с snapshot.myShots этой
    /// лунки НА МОМЕНТ первого появления. Без этой базы markConfirmed
    /// прибавлял бы acceptedCount К НУЛЮ, а не к уже-подтверждённому
    /// сервером количеству — confirmedCount(forHole:) занижался бы на
    /// величину этой базы (см. живое ревью Task 4, Fix 2: тест
    /// testConfirmedCountAdvancesFromReceiptEvenWithoutFreshSnapshot поймал
    /// именно это на первой версии фикса). Монотонно — никогда не понижает.
    func seedConfirmedCountIfHigher(roundId: String, holeNumber: Int, count: Int) {
        guard count > 0 else { return }
        ioQueue.sync {
            let key = slotKey(roundId, holeNumber)
            var confirmed = loadConfirmedLocked()
            guard count > (confirmed[key] ?? 0) else { return }
            confirmed[key] = count
            persistConfirmedLocked(confirmed)
        }
    }

    /// Стирает счётчики подтверждений УКАЗАННОГО раунда — вызывается
    /// WatchRoundViewModel при смене раунда (та же ветка, что уже сбрасывает
    /// shotsByHole). Корректность от этого не зависит — ключи уже несут
    /// roundId, поэтому счётчики прошлого раунда физически не читаются в
    /// контексте нового; это чисто гигиена, чтобы файл не рос бесконечно
    /// за много раундов подряд.
    func clearConfirmedCounts(roundId: String) {
        ioQueue.sync {
            let prefix = "\(roundId):"
            let map = loadConfirmedLocked().filter { !$0.key.hasPrefix(prefix) }
            persistConfirmedLocked(map)
        }
    }

    // MARK: публичный интерфейс — pending-хвосты

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

    /// Квитанция с телефона (WatchShotReceiptEntry). `acceptedCount` —
    /// сколько клюшек ИЗ ТЕКУЩЕГО хвоста этого слота телефон только что
    /// "закрыл" (см. `accepted` ниже для смысла этого закрытия).
    ///
    /// `accepted: true` (дефолт) — реально записано на телефоне: срезаем
    /// подтверждённый префикс (если пользователь успел добавить на часах
    /// ещё ударов, пока квитанция была в пути, остаток остаётся в
    /// очереди — уйдёт со следующим flush()) и продвигаем монотонный
    /// confirmedCount на acceptedCount.
    ///
    /// `accepted: false` (Fix 3, живое ревью Task 4) — сервер ОКОНЧАТЕЛЬНО
    /// отклонил батч (повтор с тем же payload даст ту же ошибку) — тоже
    /// продвигаем confirmedCount и срезаем хвост (ретраить бессмысленно,
    /// а бесконечный "не синхронизировано" без объяснения — плохой UX),
    /// но публикуем `.watchShotSyncFailed`, чтобы UI показал явную ошибку.
    ///
    /// Снимает флаг "в пути" в любом случае, даже если сам слот уже был
    /// снят иначе (защита от утечки состояния throttle'а).
    func markConfirmed(roundId: String, holeNumber: Int, acceptedCount: Int, accepted: Bool = true) {
        let key = slotKey(roundId, holeNumber)
        ioQueue.sync { inFlightSince.removeValue(forKey: key) }
        if acceptedCount > 0 {
            ioQueue.sync {
                var confirmed = loadConfirmedLocked()
                confirmed[key, default: 0] += acceptedCount
                persistConfirmedLocked(confirmed)
            }
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
            // confirmedCount продвинулся, но это отдельный файл от
            // pending-хвостов — withMap выше постит уведомление, только
            // если pending реально изменился (мог остаться прежним, если
            // слота уже не было). Гарантируем уведомление в любом случае,
            // иначе UI (pendingCount читает confirmedCount) не узнал бы о
            // продвижении, когда pending-слот уже был снят раньше.
            NotificationCenter.default.post(name: .watchShotQueueDidChange, object: nil)
        }
        if !accepted {
            NotificationCenter.default.post(
                name: .watchShotSyncFailed, object: nil,
                userInfo: ["roundId": roundId, "holeNumber": holeNumber]
            )
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

    private static func defaultStoreURL(name: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }
}
