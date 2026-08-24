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
// НЕТ понятия "confirmedCount" (было в Task 4 до живого ревью, удалено
// целиком) — WatchRoundViewModel больше не пытается свести в одну границу
// "сервер" и "часы": он читает snapshot.myShots и `pending` этого класса
// как две отдельные, непересекающиеся по построению величины. Это durable-
// хранилище отвечает ТОЛЬКО за сам хвост (`pending`/`enqueue`/
// `markConfirmed`) и за монотонный `sequence`/`installId`, нужные для
// идемпотентности доставки на телефон.
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
    /// Монотонный номер этой конкретной "поимки" хвоста для слота — см.
    /// WatchShotEntry.sequence (Fix 5, живое ревью Task 4). Присваивается
    /// ОДИН РАЗ при enqueue(); переотправка ЭТОГО ЖЕ объекта (flush-ретрай
    /// по таймауту) несёт то же значение, новый enqueue (реально новый
    /// удар/изменение) — большее.
    var sequence: Int
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
        sequenceStoreURL: WatchShotQueue.defaultStoreURL(name: "watch-sequence-v1.json"),
        installIdStoreURL: WatchShotQueue.defaultStoreURL(name: "watch-install-id-v1.txt")
    )

    /// Сколько ждать квитанции, прежде чем считать батч потерянным и
    /// разрешить flush() отправить слот повторно. Без таймаута слот,
    /// отправка которого молча не удалась (например, WCSession не
    /// поддерживается на этом устройстве), остался бы помеченным "в пути"
    /// навсегда и никогда не переотправился бы.
    ///
    /// ВАЖНО: таймаут открывает узкое окно, где оригинальная отправка ВСЁ
    /// ЖЕ доходит позже (например, после восстановления Bluetooth)
    /// одновременно с повторной. Это БЕЗОПАСНО с Fix 5 (живое ревью
    /// Task 4): применение на телефоне теперь идёт по монотонному
    /// `sequence` (WatchBatchSequenceLedger), а не по совпадению
    /// содержимого клюшек — повторная доставка того же sequence
    /// пропускается (но подтверждается), настоящая новая отправка несёт
    /// больший sequence и применяется как обычно.
    static let inFlightTimeout: TimeInterval = 30

    private let storeURL: URL
    private let sequenceStoreURL: URL
    private let installIdStoreURL: URL
    private let ioQueue = DispatchQueue(label: "sgc.watchshotqueue.io")
    /// НЕ персистится: после перезапуска часов судьба предыдущей отправки
    /// неизвестна — разрешаем немедленный повтор при следующем flush(),
    /// это безопасно (повторная отправка несёт тот же sequence, что и
    /// раньше — телефон его уже видел и просто подтвердит без повторной
    /// записи, см. Fix 5).
    private var inFlightSince: [String: Date] = [:]

    /// Durable-идентификатор ЭТОЙ установки приложения часов (Fix 8, живое
    /// ревью Task 4) — создаётся один раз при первом обращении и живёт,
    /// пока живут данные приложения: переживает обычный перезапуск
    /// процесса (та же файловая система, что и остальные хранилища этого
    /// класса), НЕ переживает удаление приложения (контейнер данных
    /// стирается вместе с ним). Включается в WatchShotEntry, чтобы
    /// переустановка (которая заодно обнуляет файл sequence-счётчика —
    /// тоже стёрт) не коллизировала с уже применённым на телефоне
    /// sequence прежней установки: WatchBatchSequenceLedger ключует запись
    /// по (round:holeIndex:uid:installId), поэтому новая установка
    /// автоматически получает собственное пространство sequence, а не
    /// молча "видится телефону" как повтор старого удара.
    /// Кэш прочитанного/сгенерированного значения — сам класс `@unchecked
    /// Sendable`, поэтому доступ синхронизирован через ioQueue (обычный
    /// `lazy var` не даёт такой гарантии при конкурентном обращении).
    private var installIdCache: String?

    var installId: String {
        ioQueue.sync {
            if let cached = installIdCache { return cached }
            if let existing = try? String(contentsOf: installIdStoreURL, encoding: .utf8),
               !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                installIdCache = existing
                return existing
            }
            let fresh = UUID().uuidString
            try? fresh.write(to: installIdStoreURL, atomically: true, encoding: .utf8)
            installIdCache = fresh
            return fresh
        }
    }

    init(storeURL: URL, sequenceStoreURL: URL, installIdStoreURL: URL) {
        self.storeURL = storeURL
        self.sequenceStoreURL = sequenceStoreURL
        self.installIdStoreURL = installIdStoreURL
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

    // MARK: хранилище — монотонный sequence на слот (Fix 5, живое ревью Task 4)

    /// Отдельный файл: "последний присвоенный sequence" на слот. НЕ
    /// совпадает с PendingWatchShot.sequence самого текущего хвоста — этот
    /// счётчик переживает markConfirmed-очистку слота (иначе новый
    /// enqueue после полной очистки начал бы нумерацию заново с 1, что
    /// задом наперёд совпало бы с уже применённым на телефоне sequence и
    /// заставило бы телефон молча ПРОПУСТИТЬ реально новый удар как "уже
    /// применённый").
    private func loadSequencesLocked() -> [String: Int] {
        guard let data = try? Data(contentsOf: sequenceStoreURL) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    private func persistSequencesLocked(_ map: [String: Int]) {
        if let data = try? JSONEncoder().encode(map) {
            try? data.write(to: sequenceStoreURL, options: .atomic)
        }
    }

    /// Выделяет и сохраняет следующий sequence для слота — вызывается
    /// ТОЛЬКО из enqueue() (см. её комментарий).
    private func allocateSequence(for key: String) -> Int {
        ioQueue.sync {
            var sequences = loadSequencesLocked()
            let next = (sequences[key] ?? 0) + 1
            sequences[key] = next
            persistSequencesLocked(sequences)
            return next
        }
    }

    /// Стирает счётчики sequence УКАЗАННОГО раунда — вызывается
    /// WatchRoundViewModel при смене раунда. Корректность от этого не
    /// зависит — ключи уже несут roundId, поэтому счётчики прошлого раунда
    /// физически не читаются в контексте нового; это чисто гигиена, чтобы
    /// файл не рос бесконечно за много раундов подряд.
    func clearSequences(roundId: String) {
        ioQueue.sync {
            let prefix = "\(roundId):"
            let map = loadSequencesLocked().filter { !$0.key.hasPrefix(prefix) }
            persistSequencesLocked(map)
        }
    }

    // MARK: публичный интерфейс — pending-хвосты

    /// Все ожидающие подтверждения записи — единственный источник истины
    /// для WatchRoundViewModel.pendingClubs/unsyncedShots(forHole:) и для
    /// «не синхронизировано» бейджа UI. Стабильный порядок (по номеру
    /// лунки) ради предсказуемых тестов.
    var pending: [PendingWatchShot] {
        ioQueue.sync { loadLocked() }.values.sorted { $0.holeNumber < $1.holeNumber }
    }

    /// Кладёт/перезаписывает хвост неподтверждённых ударов лунки. Слот
    /// "roundId:holeNumber" — last-write-wins: повторный enqueue той же
    /// лунки перезаписывает значение, а не накапливает историю, поэтому
    /// повтор не плодит записи. Пустой хвост снимает слот целиком —
    /// вызывающая сторона (WatchRoundViewModel.removeShot) явно решает,
    /// когда это уместно (addShot() всегда шлёт непустой хвост, снять
    /// слот целиком отсюда не может).
    ///
    /// Каждый непустой вызов выделяет НОВЫЙ sequence (allocateSequence) —
    /// это единственное место, где sequence растёт. Флаш того же
    /// объекта (throttle-ретрай) sequence НЕ меняет — только повторный
    /// enqueue (addShot/removeShot реально изменили содержимое хвоста).
    func enqueue(roundId: String, holeNumber: Int, clubs: [String]) {
        let key = slotKey(roundId, holeNumber)
        guard !clubs.isEmpty else {
            withMap { $0.removeValue(forKey: key) }
            return
        }
        let sequence = allocateSequence(for: key)
        let entry = PendingWatchShot(roundId: roundId, holeNumber: holeNumber, clubs: clubs,
                                     updatedAt: Date().timeIntervalSince1970, sequence: sequence)
        withMap { $0[key] = entry }
    }

    /// Квитанция с телефона (WatchShotReceiptEntry). `acceptedCount` —
    /// сколько клюшек ИЗ ТЕКУЩЕГО хвоста этого слота телефон только что
    /// "закрыл" (см. `accepted` ниже для смысла этого закрытия). Срезает
    /// подтверждённый префикс из `pending` — это и есть механизм,
    /// закрывающий "осознанный компромисс" WatchRoundViewModel (окно
    /// временного завышения счёта между записью на сервере и приходом
    /// квитанции): как только квитанция срезала хвост, myShots и pending
    /// снова непересекающиеся.
    ///
    /// `accepted: true` (дефолт) — реально записано на телефоне. Если
    /// пользователь успел добавить на часах ещё ударов, пока квитанция
    /// была в пути, остаток остаётся в очереди — уйдёт со следующим
    /// flush().
    ///
    /// `accepted: false` (Fix 3, живое ревью Task 4) — сервер ОКОНЧАТЕЛЬНО
    /// отклонил батч (повтор с тем же payload даст ту же ошибку) — тоже
    /// срезаем хвост (ретраить бессмысленно, а бесконечный "не
    /// синхронизировано" без объяснения — плохой UX), но публикуем
    /// `.watchShotSyncFailed`, чтобы UI показал явную ошибку.
    ///
    /// Снимает флаг "в пути" в любом случае, даже если сам слот уже был
    /// снят иначе (защита от утечки состояния throttle'а).
    func markConfirmed(roundId: String, holeNumber: Int, acceptedCount: Int, accepted: Bool = true) {
        let key = slotKey(roundId, holeNumber)
        ioQueue.sync { inFlightSince.removeValue(forKey: key) }
        if acceptedCount > 0 {
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
                WatchShotEntry(holeNumber: $0.holeNumber, clubs: $0.clubs, recordedAt: Date(timeIntervalSince1970: $0.updatedAt), sequence: $0.sequence, installId: installId)
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
