// ios/SmartGolfCaddy/Models/WatchMessages.swift
// Контракт сообщений телефон ↔ часы (WatchConnectivity). Foundation-only —
// подключается в оба таргета (iOS + watchOS) без импорта WatchConnectivity.
// Кодирование через plain [String: Any] payload (совместимо с
// updateApplicationContext/transferUserInfo, которые требуют
// property-list-совместимые значения). Корневые структуры несут "v": 1 —
// приёмник отбрасывает payload другой версии, а не пытается угадать схему.
import Foundation

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
        guard let number = payload["number"] as? Int,
              let par = payload["par"] as? Int,
              let distanceMeters = payload["distanceMeters"] as? Int,
              let myShots = payload["myShots"] as? Int else { return nil }
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
    let unitsYards: Bool
    let updatedAt: Date

    init(
        roundId: String,
        courseName: String,
        totalHoles: Int,
        holes: [WatchHole],
        clubs: [String],
        greens: [Int: GreenMark],
        activeHoleNumber: Int,
        unitsYards: Bool,
        updatedAt: Date
    ) {
        self.roundId = roundId
        self.courseName = courseName
        self.totalHoles = totalHoles
        self.holes = holes
        self.clubs = clubs
        self.greens = greens
        self.activeHoleNumber = activeHoleNumber
        self.unitsYards = unitsYards
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
            "unitsYards": unitsYards,
            "updatedAt": updatedAt.timeIntervalSince1970,
        ]
    }

    init?(payload: [String: Any]) {
        guard let version = payload["v"] as? Int, version == 1,
              let roundId = payload["roundId"] as? String,
              let courseName = payload["courseName"] as? String,
              let totalHoles = payload["totalHoles"] as? Int,
              let rawHoles = payload["holes"] as? [[String: Any]],
              let clubs = payload["clubs"] as? [String],
              let rawGreens = payload["greens"] as? [String: [String: Double]],
              let activeHoleNumber = payload["activeHoleNumber"] as? Int,
              let unitsYards = payload["unitsYards"] as? Bool,
              let updatedAtInterval = payload["updatedAt"] as? TimeInterval else { return nil }

        let holes = rawHoles.compactMap(WatchHole.init(payload:))
        guard holes.count == rawHoles.count else { return nil }

        var greens: [Int: GreenMark] = [:]
        for (key, value) in rawGreens {
            guard let hole = Int(key), let lat = value["lat"], let lng = value["lng"] else { return nil }
            greens[hole] = GreenMark(lat: lat, lng: lng)
        }

        self.roundId = roundId
        self.courseName = courseName
        self.totalHoles = totalHoles
        self.holes = holes
        self.clubs = clubs
        self.greens = greens
        self.activeHoleNumber = activeHoleNumber
        self.unitsYards = unitsYards
        self.updatedAt = Date(timeIntervalSince1970: updatedAtInterval)
    }
}

/// Один удар, записанный на часах — часть пакета `WatchShotBatch`.
struct WatchShotEntry: Equatable {
    let holeNumber: Int
    let clubs: [String]
    let recordedAt: Date

    var payload: [String: Any] {
        ["holeNumber": holeNumber, "clubs": clubs, "recordedAt": recordedAt.timeIntervalSince1970]
    }

    init(holeNumber: Int, clubs: [String], recordedAt: Date) {
        self.holeNumber = holeNumber
        self.clubs = clubs
        self.recordedAt = recordedAt
    }

    init?(payload: [String: Any]) {
        guard let holeNumber = payload["holeNumber"] as? Int,
              let clubs = payload["clubs"] as? [String],
              let recordedAtInterval = payload["recordedAt"] as? TimeInterval else { return nil }
        self.holeNumber = holeNumber
        self.clubs = clubs
        self.recordedAt = Date(timeIntervalSince1970: recordedAtInterval)
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
        guard let version = payload["v"] as? Int, version == 1,
              let roundId = payload["roundId"] as? String,
              let rawEntries = payload["entries"] as? [[String: Any]] else { return nil }

        let entries = rawEntries.compactMap(WatchShotEntry.init(payload:))
        guard entries.count == rawEntries.count else { return nil }

        self.roundId = roundId
        self.entries = entries
    }
}
