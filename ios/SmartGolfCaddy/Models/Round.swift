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
    var legacyClub: String?   // Firestore-ключ "club" (старые раунды)
    var updatedAt: Date?

    // Паритет getHoleClubs из src/types/index.ts
    var resolvedClubs: [String] {
        if !clubs.isEmpty { return clubs }
        if let legacyClub, !legacyClub.isEmpty { return Array(repeating: legacyClub, count: count) }
        return Array(repeating: "Неизвестно", count: count)
    }

    init(count: Int, clubs: [String], legacyClub: String?, updatedAt: Date?) {
        self.count = count
        self.clubs = clubs
        self.legacyClub = legacyClub
        self.updatedAt = updatedAt
    }

    init?(data: [String: Any]) {
        count = (data["count"] as? NSNumber)?.intValue ?? 0
        clubs = data["clubs"] as? [String] ?? []
        legacyClub = data["club"] as? String
        updatedAt = data["updatedAt"] as? Date
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

// Порт TEE_LABELS из src/types/index.ts — метки и цвета тии.
extension TeeColor {
    var label: String {
        switch self {
        case .pro: return "Pro"
        case .men: return "Мужские"
        case .senior: return "Сеньорские"
        case .ladies: return "Женские"
        }
    }

    var teeDescription: String {
        switch self {
        case .pro: return "Чемпионские · +10%"
        case .men: return "Стандартные"
        case .senior: return "Чуть ближе · −10%"
        case .ladies: return "Ближе всего · −20%"
        }
    }

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
