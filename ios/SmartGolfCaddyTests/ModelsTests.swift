import XCTest
@testable import SmartGolfCaddy

final class ModelsTests: XCTestCase {

    // MARK: HoleShots — паритет getHoleClubs

    func testResolvedClubsCanonical() {
        let shots = HoleShots(count: 2, clubs: ["Driver", "Putter"], distances: [], legacyClub: nil, updatedAt: nil)
        XCTAssertEqual(shots.resolvedClubs, ["Driver", "Putter"])
    }

    func testResolvedClubsLegacy() {
        let shots = HoleShots(count: 3, clubs: [], distances: [], legacyClub: "7i", updatedAt: nil)
        XCTAssertEqual(shots.resolvedClubs, ["7i", "7i", "7i"])
    }

    func testResolvedClubsUnknown() {
        let shots = HoleShots(count: 2, clubs: [], distances: [], legacyClub: nil, updatedAt: nil)
        XCTAssertEqual(shots.resolvedClubs, ["Неизвестно", "Неизвестно"])
    }

    func testResolvedClubsEmptyLegacy() {
        // Empty string legacy club should be falsy (web parity: JS if (shots.club) with "" → false)
        let shots = HoleShots(count: 2, clubs: [], distances: [], legacyClub: "", updatedAt: nil)
        XCTAssertEqual(shots.resolvedClubs, ["Неизвестно", "Неизвестно"])
    }

    // MARK: HoleShots — distances (Phase 2c GPS rangefinder)

    func testResolvedDistancesPadsToClubsLength() {
        let shots = HoleShots(count: 3, clubs: ["Driver", "7i", "Putter"],
                              distances: [215], legacyClub: nil, updatedAt: nil)
        XCTAssertEqual(shots.resolvedDistances, [215, 0, 0])
    }

    func testResolvedDistancesTrimsExtra() {
        let shots = HoleShots(count: 1, clubs: ["Driver"],
                              distances: [215, 140], legacyClub: nil, updatedAt: nil)
        XCTAssertEqual(shots.resolvedDistances, [215])
    }

    func testDistancesRoundTripThroughFirestoreData() {
        let shots = HoleShots(count: 2, clubs: ["Driver", "PW"],
                              distances: [215, 0], legacyClub: nil, updatedAt: nil)
        let restored = HoleShots(data: shots.firestoreData)
        XCTAssertEqual(restored?.distances, [215, 0])
        XCTAssertEqual(restored?.resolvedDistances, [215, 0])
    }

    // MARK: Clubs — паритет getBagFromUser / getClubLabel

    func testResolveBagPrefersCanonical() {
        let bag = [BagClub(id: "7i", customName: nil, distanceMeters: 140, enabled: true, category: nil, custom: nil)]
        let resolved = Clubs.resolveBag(bag: bag, legacyClubs: nil)
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved[0].category, .iron) // бэкфилл категории из id
    }

    func testResolveBagLegacyClubs() {
        let resolved = Clubs.resolveBag(bag: nil, legacyClubs: ["Driver", "Putter"])
        XCTAssertEqual(resolved.count, Clubs.defaultBag.count)
        XCTAssertTrue(resolved.first { $0.id == "Driver" }!.enabled)
        XCTAssertFalse(resolved.first { $0.id == "7i" }!.enabled)
    }

    func testResolveBagEmpty() {
        XCTAssertEqual(Clubs.resolveBag(bag: nil, legacyClubs: nil), Clubs.defaultBag)
    }

    func testClubLabels() {
        XCTAssertEqual(Clubs.label(for: "Driver", in: []), "DRV")
        XCTAssertEqual(Clubs.label(for: "custom-abc", in: []), "Клюшка")
        let bag = [BagClub(id: "custom-abc", customName: "Stealth 2", distanceMeters: 200, enabled: true, category: .wood, custom: true)]
        XCTAssertEqual(Clubs.label(for: "custom-abc", in: bag), "Stealth 2")
        XCTAssertEqual(Clubs.label(for: "Weird", in: []), "Weird")
    }

    func testDefaultBagShape() {
        XCTAssertEqual(Clubs.defaultBag.count, 20)
        XCTAssertEqual(Clubs.defaultBag.filter { $0.enabled }.count, 10)
    }

    // MARK: BagClub — serialization/deserialization parity

    func testBagClubRoundTrip() {
        // Create BagClub with all fields, serialize to dict, deserialize, verify equality
        let original = BagClub(id: "7i", customName: "Mighty 7", distanceMeters: 140, enabled: true, category: .iron, custom: false)
        let dict = original.firestoreData
        let restored = BagClub(dict: dict)
        XCTAssertEqual(restored, original)
    }

    func testBagClubFirestoreDataOmitsNil() {
        // firestoreData must not include keys for nil fields
        let club = BagClub(id: "Driver", customName: nil, distanceMeters: 230, enabled: true, category: nil, custom: nil)
        let dict = club.firestoreData
        XCTAssertFalse(dict.keys.contains("customName"))
        XCTAssertFalse(dict.keys.contains("category"))
        XCTAssertFalse(dict.keys.contains("custom"))
        XCTAssertTrue(dict.keys.contains("id"))
        XCTAssertTrue(dict.keys.contains("distanceMeters"))
        XCTAssertTrue(dict.keys.contains("enabled"))
    }

    func testBagClubDictMissingId() {
        // Missing "id" key should return nil
        let dict: [String: Any] = ["distanceMeters": 140, "enabled": true]
        XCTAssertNil(BagClub(dict: dict))
    }

    func testBagClubDictMinimal() {
        // Just id with defaults for missing fields
        let dict: [String: Any] = ["id": "7i"]
        let club = BagClub(dict: dict)
        XCTAssertNotNil(club)
        XCTAssertEqual(club?.id, "7i")
        XCTAssertNil(club?.customName)
        XCTAssertEqual(club?.distanceMeters, 0)
        XCTAssertEqual(club?.enabled, false)
        XCTAssertNil(club?.category)
        XCTAssertNil(club?.custom)
    }

    func testBagClubDictUnknownCategory() {
        // Unknown category string should become nil
        let dict: [String: Any] = ["id": "7i", "distanceMeters": 140, "enabled": true, "category": "banana"]
        let club = BagClub(dict: dict)
        XCTAssertNotNil(club)
        XCTAssertNil(club?.category)
    }

    // MARK: AppUser

    func testAppUserFromFirestoreData() {
        let user = AppUser(uid: "u1", data: [
            "name": "Джамбулат", "avatar": "https://a.jpg", "handicap": 12,
            "clubs": ["Driver", "Putter"],
        ])
        XCTAssertEqual(user?.name, "Джамбулат")
        XCTAssertEqual(user?.handicap, 12)
        XCTAssertNil(user?.bag)
        XCTAssertEqual(user?.resolvedBag.filter { $0.enabled }.count, 2)
        XCTAssertNil(user?.locale) // absent field → caller falls back to device language
    }

    func testAppUserLocaleRoundTrips() {
        let ru = AppUser(uid: "u1", data: ["name": "Д", "locale": "ru"])
        XCTAssertEqual(ru?.locale, .ru)

        let en = AppUser(uid: "u1", data: ["name": "D", "locale": "en"])
        XCTAssertEqual(en?.locale, .en)
    }

    func testAppUserUnknownLocaleBecomesNil() {
        let user = AppUser(uid: "u1", data: ["name": "Д", "locale": "fr"])
        XCTAssertNil(user?.locale)
    }

    // MARK: Round

    func testRoundFromFirestoreData() {
        let now = Date()
        let round = Round(id: "r1", data: [
            "courseId": "c1", "courseName": "Сколково", "totalHoles": 9,
            "lobbyCode": "ABC123", "status": "active", "hostId": "u1",
            "players": ["u1": ["name": "Д", "avatar": "", "totalScore": 5, "scoreDiff": 1]],
            "playerIds": ["u1"],
            "holes": [["holeNumber": 1, "par": 4, "distanceMeters": 360,
                       "shots": ["u1": ["count": 2, "clubs": ["Driver", "Putter"], "updatedAt": now]]]],
            "startedAt": now, "createdAt": now,
        ])
        XCTAssertEqual(round?.status, .active)
        XCTAssertEqual(round?.tee, .men)          // дефолт при отсутствии
        XCTAssertEqual(round?.playMode, .stroke)  // дефолт при отсутствии
        XCTAssertNil(round?.finishedAt)
        XCTAssertEqual(round?.holes.first?.shots["u1"]?.resolvedClubs, ["Driver", "Putter"])
        XCTAssertEqual(round?.players["u1"]?.totalScore, 5)
    }

    func testTeeMultipliers() {
        XCTAssertEqual(TeeColor.pro.multiplier, 1.10)
        XCTAssertEqual(TeeColor.ladies.multiplier, 0.80)
    }

    // MARK: Score — паритет scoreColor/scoreOnColor/scoreDirection/scoreLabel

    func testScorePalette() {
        XCTAssertEqual(Score.color(-2), "#FFD700"); XCTAssertEqual(Score.onColor(-2), "#1A1C1C")
        XCTAssertEqual(Score.color(-1), "#2E7D32"); XCTAssertEqual(Score.onColor(-1), "#FFFFFF")
        XCTAssertEqual(Score.color(0), "#FFFFFF");  XCTAssertEqual(Score.onColor(0), "#1A1C1C")
        XCTAssertEqual(Score.color(1), "#EF6C00");  XCTAssertEqual(Score.onColor(1), "#1A1C1C")
        XCTAssertEqual(Score.color(3), "#C62828");  XCTAssertEqual(Score.onColor(3), "#FFFFFF")
    }

    func testScoreDirectionAndLabel() {
        XCTAssertEqual(Score.direction(-1), .under)
        XCTAssertEqual(Score.direction(0), .par)
        XCTAssertEqual(Score.direction(2), .over)
        XCTAssertEqual(Score.label(-2), "Eagle")
        XCTAssertEqual(Score.label(4), "+4")
    }

    func testUnits() {
        XCTAssertEqual(Score.metersToYards(100), 109)
        XCTAssertEqual(Score.yardsToMeters(109), 100)
    }

    // MARK: pluralRu

    func testPluralRu() {
        XCTAssertEqual(pluralRu(1, "лунка", "лунки", "лунок"), "лунка")
        XCTAssertEqual(pluralRu(3, "лунка", "лунки", "лунок"), "лунки")
        XCTAssertEqual(pluralRu(5, "лунка", "лунки", "лунок"), "лунок")
        XCTAssertEqual(pluralRu(11, "лунка", "лунки", "лунок"), "лунок")
        XCTAssertEqual(pluralRu(21, "лунка", "лунки", "лунок"), "лунка")
    }
}
