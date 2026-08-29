import Foundation

enum ClubCategory: String, Codable {
    case wood, iron, wedge, putter
}

struct BagClub: Equatable, Identifiable {
    var id: String
    var customName: String?
    var distanceMeters: Int
    var enabled: Bool
    var category: ClubCategory?
    var custom: Bool?

    init(id: String, customName: String?, distanceMeters: Int, enabled: Bool,
         category: ClubCategory?, custom: Bool?) {
        self.id = id
        self.customName = customName
        self.distanceMeters = distanceMeters
        self.enabled = enabled
        self.category = category
        self.custom = custom
    }

    init?(dict: [String: Any]) {
        guard let id = dict["id"] as? String else { return nil }
        self.id = id
        customName = dict["customName"] as? String
        distanceMeters = (dict["distanceMeters"] as? NSNumber)?.intValue ?? 0
        enabled = dict["enabled"] as? Bool ?? false
        category = (dict["category"] as? String).flatMap(ClubCategory.init(rawValue:))
        custom = dict["custom"] as? Bool
    }

    var firestoreData: [String: Any] {
        var d: [String: Any] = ["id": id, "distanceMeters": distanceMeters, "enabled": enabled]
        if let customName { d["customName"] = customName }
        if let category { d["category"] = category.rawValue }
        if let custom { d["custom"] = custom }
        return d
    }
}

enum Clubs {
    /// Псевдо-клюшка «Штраф»: пишется в серию как обычный удар (счёт +1 по
    /// правилам гольфа), исключается из статистики клюшек. SYNC: PENALTY_ID
    /// в src/types/index.ts. Ключ данных, синхронизированный с вебом/базой —
    /// НЕ переводить (T4).
    static let penaltyId = "Штраф"

    /// T4: внутренний sentinel для ударов старых документов, у которых есть
    /// count, но нет ни clubs, ни legacyClub (см. HoleShots.resolvedClubs в
    /// Round.swift) — никогда не пишется в Firestore, никогда не
    /// показывается напрямую. `label(for:in:)` переводит его на текущий
    /// язык; Scoring.clubUsage сравнивает с этой же константой, а не с
    /// локализованным текстом, чтобы исключение из статистики не зависело
    /// от выбранного языка.
    static let unknownId = "__unknown_club__"

    static let abbrev: [String: String] = [
        "Driver": "DRV", "3W": "3W", "5W": "5W", "Hybrid": "HY",
        "3i": "3i", "4i": "4i", "5i": "5i", "6i": "6i", "7i": "7i", "8i": "8i", "9i": "9i",
        "PW": "PW", "GW": "GW", "SW": "SW", "LW": "LW",
        "50°": "50°", "54°": "54°", "58°": "58°", "60°": "60°",
        "Putter": "PT",
    ]

    // T4: label больше не хранится статически — переводится динамически
    // через categoryLabel(_:), иначе смена языка требовала бы пересборки
    // этого массива на каждый рендер.
    static let groups: [(category: ClubCategory, defaultIds: [String])] = [
        (.wood, ["Driver", "3W", "5W", "Hybrid"]),
        (.iron, ["3i", "4i", "5i", "6i", "7i", "8i", "9i"]),
        (.wedge, ["PW", "GW", "50°", "SW", "54°", "58°", "LW", "60°"]),
        (.putter, ["Putter"]),
    ]

    static func categoryLabel(_ category: ClubCategory) -> String {
        let clubs = AppLocaleStore.strings.clubs
        switch category {
        case .wood: return clubs.categoryWood
        case .iron: return clubs.categoryIron
        case .wedge: return clubs.categoryWedge
        case .putter: return clubs.categoryPutter
        }
    }

    static let defaultBag: [BagClub] = [
        BagClub(id: "Driver", customName: nil, distanceMeters: 230, enabled: true, category: .wood, custom: nil),
        BagClub(id: "3W", customName: nil, distanceMeters: 210, enabled: true, category: .wood, custom: nil),
        BagClub(id: "5W", customName: nil, distanceMeters: 195, enabled: false, category: .wood, custom: nil),
        BagClub(id: "Hybrid", customName: nil, distanceMeters: 185, enabled: false, category: .wood, custom: nil),
        BagClub(id: "3i", customName: nil, distanceMeters: 185, enabled: false, category: .iron, custom: nil),
        BagClub(id: "4i", customName: nil, distanceMeters: 175, enabled: false, category: .iron, custom: nil),
        BagClub(id: "5i", customName: nil, distanceMeters: 165, enabled: true, category: .iron, custom: nil),
        BagClub(id: "6i", customName: nil, distanceMeters: 150, enabled: true, category: .iron, custom: nil),
        BagClub(id: "7i", customName: nil, distanceMeters: 140, enabled: true, category: .iron, custom: nil),
        BagClub(id: "8i", customName: nil, distanceMeters: 125, enabled: true, category: .iron, custom: nil),
        BagClub(id: "9i", customName: nil, distanceMeters: 110, enabled: true, category: .iron, custom: nil),
        BagClub(id: "PW", customName: nil, distanceMeters: 95, enabled: true, category: .wedge, custom: nil),
        BagClub(id: "GW", customName: nil, distanceMeters: 85, enabled: false, category: .wedge, custom: nil),
        BagClub(id: "50°", customName: nil, distanceMeters: 85, enabled: false, category: .wedge, custom: nil),
        BagClub(id: "SW", customName: nil, distanceMeters: 70, enabled: true, category: .wedge, custom: nil),
        BagClub(id: "54°", customName: nil, distanceMeters: 75, enabled: false, category: .wedge, custom: nil),
        BagClub(id: "58°", customName: nil, distanceMeters: 60, enabled: false, category: .wedge, custom: nil),
        BagClub(id: "LW", customName: nil, distanceMeters: 55, enabled: false, category: .wedge, custom: nil),
        BagClub(id: "60°", customName: nil, distanceMeters: 55, enabled: false, category: .wedge, custom: nil),
        BagClub(id: "Putter", customName: nil, distanceMeters: 0, enabled: true, category: .putter, custom: nil),
    ]

    static func category(of club: BagClub) -> ClubCategory {
        if let category = club.category { return category }
        for group in groups where group.defaultIds.contains(club.id) { return group.category }
        return .iron
    }

    static func resolveBag(bag: [BagClub]?, legacyClubs: [String]?) -> [BagClub] {
        if let bag, !bag.isEmpty {
            return bag.map { club in
                if club.category != nil { return club }
                var patched = club
                patched.category = category(of: club)
                return patched
            }
        }
        if let legacyClubs, !legacyClubs.isEmpty {
            let enabled = Set(legacyClubs)
            return defaultBag.map { club in
                var patched = club
                patched.enabled = enabled.contains(club.id)
                return patched
            }
        }
        return defaultBag
    }

    static func label(for clubId: String, in bag: [BagClub]) -> String {
        if clubId == unknownId { return AppLocaleStore.strings.common.unknown }
        if let known = abbrev[clubId] { return known }
        if let club = bag.first(where: { $0.id == clubId }),
           let name = club.customName, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        if clubId.hasPrefix("custom-") { return AppLocaleStore.strings.clubs.missingCustom }
        return clubId
    }
}
