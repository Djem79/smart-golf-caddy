import Foundation

enum RoundStatus: String {
    case lobby, active, finished
}

enum PlayMode: String {
    case stroke, match
}

enum TeeColor: String, CaseIterable {
    case pro, men, senior, ladies

    var multiplier: Double {
        switch self {
        case .pro: return 1.10
        case .men: return 1.00
        case .senior: return 0.90
        case .ladies: return 0.80
        }
    }
}

struct HoleShots: Equatable {
    var count: Int
    var clubs: [String]
    var distances: [Int]      // метры; 0 = неизвестно. Длина выравнивается по clubs.
    var legacyClub: String?   // Firestore-ключ "club" (старые раунды)
    var updatedAt: Date?

    // Паритет getHoleClubs из src/types/index.ts
    var resolvedClubs: [String] {
        if !clubs.isEmpty { return clubs }
        if let legacyClub, !legacyClub.isEmpty { return Array(repeating: legacyClub, count: count) }
        // T4: не локализованная строка — стабильный внутренний sentinel.
        // Clubs.label(for:in:) переводит его в отображаемый текст на
        // текущем языке; Scoring.clubUsage сравнивает с этой же константой,
        // чтобы исключить эти удары из статистики клюшек независимо от
        // выбранного языка.
        return Array(repeating: Clubs.unknownId, count: count)
    }

    /// Дистанции, выровненные по длине серии: недостающие — 0, лишние отброшены.
    /// Инвариант хранения (distances.count == clubs.count) может нарушиться
    /// у документов, записанных старыми клиентами — здесь он восстанавливается.
    var resolvedDistances: [Int] {
        let target = resolvedClubs.count
        if distances.count == target { return distances }
        if distances.count > target { return Array(distances.prefix(target)) }
        return distances + Array(repeating: 0, count: target - distances.count)
    }

    init(count: Int, clubs: [String], distances: [Int], legacyClub: String?, updatedAt: Date?) {
        self.count = count
        self.clubs = clubs
        self.distances = distances
        self.legacyClub = legacyClub
        self.updatedAt = updatedAt
    }

    init?(data: [String: Any]) {
        count = (data["count"] as? NSNumber)?.intValue ?? 0
        clubs = data["clubs"] as? [String] ?? []
        distances = (data["distances"] as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue } ?? []
        legacyClub = data["club"] as? String
        updatedAt = data["updatedAt"] as? Date
    }

    var firestoreData: [String: Any] {
        var d: [String: Any] = ["count": count, "clubs": clubs, "distances": distances]
        if let legacyClub { d["club"] = legacyClub }
        if let updatedAt { d["updatedAt"] = updatedAt }
        return d
    }
}

struct PlayerInfo: Equatable {
    var name: String
    var avatar: String
    var totalScore: Int
    var scoreDiff: Int
    var email: String?

    init?(data: [String: Any]) {
        name = data["name"] as? String ?? ""
        avatar = data["avatar"] as? String ?? ""
        totalScore = (data["totalScore"] as? NSNumber)?.intValue ?? 0
        scoreDiff = (data["scoreDiff"] as? NSNumber)?.intValue ?? 0
        email = data["email"] as? String
    }

    init(name: String, avatar: String, totalScore: Int, scoreDiff: Int, email: String?) {
        self.name = name
        self.avatar = avatar
        self.totalScore = totalScore
        self.scoreDiff = scoreDiff
        self.email = email
    }

    var firestoreData: [String: Any] {
        var d: [String: Any] = ["name": name, "avatar": avatar,
                                "totalScore": totalScore, "scoreDiff": scoreDiff]
        if let email { d["email"] = email }
        return d
    }

    /// Локализованное имя для показа: переводит маркер удалённого игрока
    /// (или старый русский литерал) через `Players.displayName(_:)`;
    /// обычные имена возвращаются как есть.
    var displayName: String { Players.displayName(name) }
}

enum Players {
    /// Локально-нейтральный маркер: пишется `deleteAccount()`
    /// (functions/src/index.ts) в `players.{uid}.name` при обезличивании
    /// участника группового раунда, вместо строки на конкретном языке.
    /// SYNC: DELETED_PLAYER_MARKER в src/types/index.ts и
    /// functions/src/emails/buildPayload.ts — литерал должен совпадать
    /// буквально во всех трёх местах.
    static let deletedMarker = "__deleted_player__"

    /// Значение, которое `deleteAccount()` писал ДО появления маркера.
    /// Раунды, обезличенные до этого изменения, хранят именно эту русскую
    /// строку — это чужие данные (принадлежат другим игрокам), поэтому
    /// миграция исключена: displayName(_:) распознаёт оба значения
    /// бессрочно.
    private static let legacyDeletedNameRU = "Удалённый игрок"

    /// Переводит маркер удалённого игрока (новый или старый литерал) в
    /// текущий язык через `AppLocaleStore.strings.common.deletedPlayerName`;
    /// любое другое имя возвращается без изменений.
    static func displayName(_ name: String) -> String {
        (name == deletedMarker || name == legacyDeletedNameRU)
            ? AppLocaleStore.strings.common.deletedPlayerName
            : name
    }
}

struct HoleConfig: Equatable {
    var holeNumber: Int
    var par: Int
    var distanceMeters: Int
    var shots: [String: HoleShots]

    init?(data: [String: Any]) {
        holeNumber = (data["holeNumber"] as? NSNumber)?.intValue ?? 0
        par = (data["par"] as? NSNumber)?.intValue ?? 4
        distanceMeters = (data["distanceMeters"] as? NSNumber)?.intValue ?? 0
        var parsed: [String: HoleShots] = [:]
        for (uid, raw) in data["shots"] as? [String: [String: Any]] ?? [:] {
            parsed[uid] = HoleShots(data: raw)
        }
        shots = parsed
    }

    var firestoreData: [String: Any] {
        [
            "holeNumber": holeNumber,
            "par": par,
            "distanceMeters": distanceMeters,
            "shots": shots.mapValues { $0.firestoreData },
        ]
    }
}

struct Round: Equatable, Identifiable {
    let id: String
    var courseId: String
    var courseName: String
    var totalHoles: Int
    var lobbyCode: String
    var status: RoundStatus
    var hostId: String
    var players: [String: PlayerInfo]
    var playerIds: [String]
    var tee: TeeColor
    var playMode: PlayMode
    var holes: [HoleConfig]
    var startedAt: Date?    // nil, пока групповой раунд в лобби
    var finishedAt: Date?
    var createdAt: Date

    // Паритет normalizeRound из src/services/rounds.ts
    init?(id: String, data: [String: Any]) {
        guard let statusRaw = data["status"] as? String,
              let status = RoundStatus(rawValue: statusRaw) else { return nil }
        self.id = id
        self.status = status
        courseId = data["courseId"] as? String ?? ""
        courseName = data["courseName"] as? String ?? ""
        totalHoles = (data["totalHoles"] as? NSNumber)?.intValue ?? 18
        lobbyCode = data["lobbyCode"] as? String ?? ""
        hostId = data["hostId"] as? String ?? ""
        var parsedPlayers: [String: PlayerInfo] = [:]
        for (uid, raw) in data["players"] as? [String: [String: Any]] ?? [:] {
            parsedPlayers[uid] = PlayerInfo(data: raw)
        }
        players = parsedPlayers
        playerIds = data["playerIds"] as? [String] ?? []
        tee = (data["tee"] as? String).flatMap(TeeColor.init(rawValue:)) ?? .men
        playMode = (data["playMode"] as? String).flatMap(PlayMode.init(rawValue:)) ?? .stroke
        holes = (data["holes"] as? [[String: Any]] ?? []).compactMap(HoleConfig.init(data:))
        startedAt = data["startedAt"] as? Date
        finishedAt = data["finishedAt"] as? Date
        createdAt = data["createdAt"] as? Date ?? Date()
    }
}

// Порт TEE_COLORS (цвета) и t.common.tee (метки, src/i18n/ru.ts+en.ts) из веба — тии.
extension TeeColor {
    private var info: Strings.Common.TeeInfo {
        let tee = AppLocaleStore.strings.common.tee
        switch self {
        case .pro: return tee.pro
        case .men: return tee.men
        case .senior: return tee.senior
        case .ladies: return tee.ladies
        }
    }

    var label: String { info.label }
    var teeDescription: String { info.description }

    var bgHex: String {
        switch self {
        case .pro: return "#0A3010"
        case .men: return "#FFFFFF"
        case .senior: return "#FFC107"
        case .ladies: return "#F44336"
        }
    }

    var textHex: String {
        switch self {
        case .pro: return "#FFFFFF"
        case .men: return "#1A1C1C"
        case .senior: return "#1A1C1C"
        case .ladies: return "#FFFFFF"
        }
    }
}
