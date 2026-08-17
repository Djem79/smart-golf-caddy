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
    static let abbrev: [String: String] = [
        "Driver": "DRV", "3W": "3W", "5W": "5W", "Hybrid": "HY",
        "3i": "3i", "4i": "4i", "5i": "5i", "6i": "6i", "7i": "7i", "8i": "8i", "9i": "9i",
        "PW": "PW", "GW": "GW", "SW": "SW", "LW": "LW",
        "50°": "50°", "54°": "54°", "58°": "58°", "60°": "60°",
        "Putter": "PT",
    ]

    static let groups: [(category: ClubCategory, label: String, defaultIds: [String])] = [
        (.wood, "Драйвер и вуды", ["Driver", "3W", "5W", "Hybrid"]),
        (.iron, "Айроны", ["3i", "4i", "5i", "6i", "7i", "8i", "9i"]),
        (.wedge, "Вейджи", ["PW", "GW", "50°", "SW", "54°", "58°", "LW", "60°"]),
        (.putter, "Паттер", ["Putter"]),
    ]

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
        if let known = abbrev[clubId] { return known }
        if let club = bag.first(where: { $0.id == clubId }),
           let name = club.customName, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        if clubId.hasPrefix("custom-") { return "Клюшка" }
        return clubId
    }
}
