// ios/SmartGolfCaddy/Models/WatchMessages.swift
// Контракт сообщений телефон ↔ часы (WatchConnectivity). Foundation-only —
// подключается в оба таргета (iOS + watchOS) без импорта WatchConnectivity.
// Кодирование через plain [String: Any] payload (совместимо с
// updateApplicationContext/transferUserInfo, которые требуют
// property-list-совместимые значения). Корневые структуры несут "v": 1 —
// приёмник отбрасывает payload другой версии, а не пытается угадать схему.
import Foundation

// updateApplicationContext/transferUserInfo гоняют payload через
// property-list/XPC — по ту сторону числа приходят как NSNumber, поэтому
// строгий `as? Int`/`as? Double` может дать nil даже для валидных данных
// (см. канон паттерна: Club.swift:29, GreenMarks.swift:24-25, Round.swift
// HoleConfig). `as? NSNumber` бриджит и нативные Swift Int/Double/Bool
// (round-trip в одном процессе, как в тестах), и настоящий NSNumber из XPC.
private func watchIntValue(_ any: Any?) -> Int? { (any as? NSNumber)?.intValue }
private func watchDoubleValue(_ any: Any?) -> Double? { (any as? NSNumber)?.doubleValue }
private func watchBoolValue(_ any: Any?) -> Bool? { (any as? NSNumber)?.boolValue }

/// Одна лунка в снимке раунда, отправляемом на часы.
struct WatchHole: Equatable {
    let number: Int
    let par: Int
    let distanceMeters: Int
    let myShots: Int

    var payload: [String: Any] {
        ["number": number, "par": par, "distanceMeters": distanceMeters, "myShots": myShots]
    }

    init(number: Int, par: Int, distanceMeters: Int, myShots: Int) {
        self.number = number
        self.par = par
        self.distanceMeters = distanceMeters
        self.myShots = myShots
    }

    init?(payload: [String: Any]) {
        guard let number = watchIntValue(payload["number"]),
              let par = watchIntValue(payload["par"]),
              let distanceMeters = watchIntValue(payload["distanceMeters"]),
              let myShots = watchIntValue(payload["myShots"]) else { return nil }
        self.number = number
        self.par = par
        self.distanceMeters = distanceMeters
        self.myShots = myShots
    }
}

/// Снимок активного раунда: телефон → часы, через `updateApplicationContext`
/// (последнее состояние всегда актуально, старые снимки перезаписываются).
struct WatchRoundSnapshot: Equatable {
    let roundId: String
    let courseName: String
    let totalHoles: Int
    let holes: [WatchHole]
    let clubs: [String]
    let greens: [Int: GreenMark]
    let activeHoleNumber: Int
    let units: DistanceUnit
    let updatedAt: Date

    init(
        roundId: String,
        courseName: String,
        totalHoles: Int,
        holes: [WatchHole],
        clubs: [String],
        greens: [Int: GreenMark],
        activeHoleNumber: Int,
        units: DistanceUnit,
        updatedAt: Date
    ) {
        self.roundId = roundId
        self.courseName = courseName
        self.totalHoles = totalHoles
        self.holes = holes
        self.clubs = clubs
        self.greens = greens
        self.activeHoleNumber = activeHoleNumber
        self.units = units
        self.updatedAt = updatedAt
    }

    var payload: [String: Any] {
        var greensPayload: [String: [String: Double]] = [:]
        for (hole, mark) in greens {
            greensPayload[String(hole)] = ["lat": mark.lat, "lng": mark.lng]
        }
        return [
            "v": 1,
            "roundId": roundId,
            "courseName": courseName,
            "totalHoles": totalHoles,
            "holes": holes.map(\.payload),
            "clubs": clubs,
            "greens": greensPayload,
            "activeHoleNumber": activeHoleNumber,
            "units": units.rawValue,
            "updatedAt": updatedAt.timeIntervalSince1970,
        ]
    }

    init?(payload: [String: Any]) {
        guard let version = watchIntValue(payload["v"]), version == 1,
              let roundId = payload["roundId"] as? String,
              let courseName = payload["courseName"] as? String,
              let totalHoles = watchIntValue(payload["totalHoles"]),
              let rawHoles = payload["holes"] as? [[String: Any]],
              let clubs = payload["clubs"] as? [String],
              let rawGreens = payload["greens"] as? [String: Any],
              let activeHoleNumber = watchIntValue(payload["activeHoleNumber"]),
              let unitsRaw = payload["units"] as? String,
              let units = DistanceUnit(rawValue: unitsRaw),
              let updatedAtInterval = watchDoubleValue(payload["updatedAt"]) else { return nil }

        let holes = rawHoles.compactMap(WatchHole.init(payload:))
        guard holes.count == rawHoles.count else { return nil }

        // Одна битая метка грина не должна убивать весь снимок — пропускаем
        // только её, а не проваливаем декодирование целиком.
        var greens: [Int: GreenMark] = [:]
        for (key, value) in rawGreens {
            guard let hole = Int(key),
                  let markDict = value as? [String: Any],
                  let lat = watchDoubleValue(markDict["lat"]),
                  let lng = watchDoubleValue(markDict["lng"]) else { continue }
            greens[hole] = GreenMark(lat: lat, lng: lng)
        }

        self.roundId = roundId
        self.courseName = courseName
        self.totalHoles = totalHoles
        self.holes = holes
        self.clubs = clubs
        self.greens = greens
        self.activeHoleNumber = activeHoleNumber
        self.units = units
        self.updatedAt = Date(timeIntervalSince1970: updatedAtInterval)
    }
}

/// Один удар, записанный на часах — часть пакета `WatchShotBatch`.
struct WatchShotEntry: Equatable {
    let holeNumber: Int
    let clubs: [String]
    let recordedAt: Date
    /// Монотонный номер отправки для слота "roundId:holeNumber" (Fix 5,
    /// живое ревью Task 4) — присваивается часами при enqueue() и
    /// сохраняется durable рядом с очередью (WatchShotQueue), НЕ
    /// пересчитывается на пустом месте при повторной отправке того же
    /// слота. Телефон сверяет с последним применённым sequence для этого
    /// слота (WatchBatchSequenceLedger): sequence ≤ последнего
    /// применённого — батч уже применён, писать НЕ нужно (но квитанцию
    /// всё равно шлём, иначе слот на часах зависнет). Заменяет
    /// suffix-эвристику по содержимому клюшек, которая путала "этот батч
    /// уже применён" с "игрок ударил той же клюшкой ещё раз" (второй патт
    /// подряд, например) — см. живое ревью.
    let sequence: Int
    /// Durable-идентификатор УСТАНОВКИ приложения часов, приславшей этот
    /// батч (Fix 8, живое ревью Task 4) — см. WatchShotQueue.installId.
    /// Без него переустановка приложения часов посреди раунда обнуляет
    /// файл sequence-счётчика на часах, и новый настоящий удар с
    /// sequence=1 совпал бы с уже применённым на телефоне sequence
    /// ПРЕЖНЕЙ установки — телефон молча счёл бы его повтором.
    /// WatchBatchSequenceLedger ключует "последний применённый sequence"
    /// по (round:holeIndex:uid:installId), так что переустановка получает
    /// собственное пространство sequence по построению.
    let installId: String

    var payload: [String: Any] {
        ["holeNumber": holeNumber, "clubs": clubs, "recordedAt": recordedAt.timeIntervalSince1970, "sequence": sequence, "installId": installId]
    }

    init(holeNumber: Int, clubs: [String], recordedAt: Date, sequence: Int, installId: String) {
        self.holeNumber = holeNumber
        self.clubs = clubs
        self.recordedAt = recordedAt
        self.sequence = sequence
        self.installId = installId
    }

    init?(payload: [String: Any]) {
        guard let holeNumber = watchIntValue(payload["holeNumber"]),
              let clubs = payload["clubs"] as? [String],
              let recordedAtInterval = watchDoubleValue(payload["recordedAt"]),
              let sequence = watchIntValue(payload["sequence"]),
              let installId = payload["installId"] as? String, !installId.isEmpty else { return nil }
        self.holeNumber = holeNumber
        self.clubs = clubs
        self.recordedAt = Date(timeIntervalSince1970: recordedAtInterval)
        self.sequence = sequence
        self.installId = installId
    }
}

/// Пакет ударов: часы → телефон, через `transferUserInfo` (доставка
/// гарантирована — переживает недоступность телефона, доставляется позже).
struct WatchShotBatch: Equatable {
    let roundId: String
    let entries: [WatchShotEntry]

    init(roundId: String, entries: [WatchShotEntry]) {
        self.roundId = roundId
        self.entries = entries
    }

    var payload: [String: Any] {
        ["v": 1, "roundId": roundId, "entries": entries.map(\.payload)]
    }

    init?(payload: [String: Any]) {
        guard let version = watchIntValue(payload["v"]), version == 1,
              let roundId = payload["roundId"] as? String,
              let rawEntries = payload["entries"] as? [[String: Any]] else { return nil }

        let entries = rawEntries.compactMap(WatchShotEntry.init(payload:))
        guard entries.count == rawEntries.count else { return nil }

        self.roundId = roundId
        self.entries = entries
    }
}

/// Одна квитанция по лунке: часть `WatchShotReceipt`.
struct WatchShotReceiptEntry: Equatable {
    let holeNumber: Int
    /// Сколько клюшек ИЗ ЭТОГО хвоста телефон только что "закрыл" — либо
    /// реально записал (accepted: true), либо ОКОНЧАТЕЛЬНО отклонил
    /// сервер (accepted: false, Fix 3 живого ревью Task 4) — НЕ общий счёт
    /// ударов лунки. В обоих случаях часы срезают ровно этот префикс своей
    /// очереди (WatchShotQueue.markConfirmed) — остаток, если пользователь
    /// успел добавить удар, пока квитанция была в пути, остаётся в очереди.
    let acceptedCount: Int
    /// true — recordShot принял эти клюшки (синхронно или через офлайн-
    /// очередь ShotQueue на телефоне). false — сервер ОКОНЧАТЕЛЬНО отверг
    /// запись (permanent error, повтор с тем же payload даст ту же ошибку)
    /// — часы всё равно снимают слот (ретраить бессмысленно), но помечают
    /// лунку как "не удалось синхронизировать", а не тихо подтверждённой.
    let accepted: Bool

    var payload: [String: Any] {
        ["holeNumber": holeNumber, "acceptedCount": acceptedCount, "accepted": accepted]
    }

    init(holeNumber: Int, acceptedCount: Int, accepted: Bool = true) {
        self.holeNumber = holeNumber
        self.acceptedCount = acceptedCount
        self.accepted = accepted
    }

    init?(payload: [String: Any]) {
        guard let holeNumber = watchIntValue(payload["holeNumber"]),
              let acceptedCount = watchIntValue(payload["acceptedCount"]),
              let accepted = watchBoolValue(payload["accepted"]) else { return nil }
        self.holeNumber = holeNumber
        self.acceptedCount = acceptedCount
        self.accepted = accepted
    }
}

/// Квитанция о приёме батча ударов: телефон → часы, через `transferUserInfo`
/// (тот же гарантированный канал, что и WatchShotBatch, в обратную
/// сторону). Означает "recordShot успешно отработал на телефоне для этих
/// клюшек" — НЕ просто факт получения WCSession-сообщения. Часы по ней
/// чистят/подрезают WatchShotQueue (см. WatchShotQueue.markConfirmed).
struct WatchShotReceipt: Equatable {
    let roundId: String
    let entries: [WatchShotReceiptEntry]

    init(roundId: String, entries: [WatchShotReceiptEntry]) {
        self.roundId = roundId
        self.entries = entries
    }

    var payload: [String: Any] {
        ["v": 1, "roundId": roundId, "entries": entries.map(\.payload)]
    }

    init?(payload: [String: Any]) {
        guard let version = watchIntValue(payload["v"]), version == 1,
              let roundId = payload["roundId"] as? String,
              let rawEntries = payload["entries"] as? [[String: Any]] else { return nil }

        let entries = rawEntries.compactMap(WatchShotReceiptEntry.init(payload:))
        guard entries.count == rawEntries.count else { return nil }

        self.roundId = roundId
        self.entries = entries
    }
}
