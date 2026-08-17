import Foundation

enum DistanceUnit: String, Codable {
    case m, yd
}

struct AppUser: Equatable {
    let uid: String
    var name: String
    var avatar: String
    var handicap: Double
    var bag: [BagClub]?
    var units: DistanceUnit?
    var legacyClubs: [String]?   // Firestore-ключ "clubs" (pre-bag rollout)

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
    }
}
