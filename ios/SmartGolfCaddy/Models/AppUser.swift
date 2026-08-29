import Foundation

enum DistanceUnit: String, Codable {
    case m, yd
}

// SYNC: mirrors `AppUser['locale']` in src/types/index.ts. Absent → caller
// falls back to the device language. No UI reads/writes this yet — that's
// T4 (this model only needs to round-trip the field so the app keeps
// building and Firestore documents with `locale` decode cleanly).
enum AppLocale: String, Codable {
    case ru, en
}

struct AppUser: Equatable {
    let uid: String
    var name: String
    var avatar: String
    var handicap: Double
    var bag: [BagClub]?
    var units: DistanceUnit?
    var legacyClubs: [String]?   // Firestore-ключ "clubs" (pre-bag rollout)
    var locale: AppLocale?

    var resolvedBag: [BagClub] { Clubs.resolveBag(bag: bag, legacyClubs: legacyClubs) }

    init?(uid: String, data: [String: Any]) {
        self.uid = uid
        name = data["name"] as? String ?? "Golfer"
        avatar = data["avatar"] as? String ?? ""
        handicap = (data["handicap"] as? NSNumber)?.doubleValue ?? 0
        if let rawBag = data["bag"] as? [[String: Any]] {
            let parsed = rawBag.compactMap(BagClub.init(dict:))
            bag = parsed.isEmpty ? nil : parsed
        }
        units = (data["units"] as? String).flatMap(DistanceUnit.init(rawValue:))
        legacyClubs = data["clubs"] as? [String]
        locale = (data["locale"] as? String).flatMap(AppLocale.init(rawValue:))
    }
}
