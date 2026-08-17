import XCTest
@testable import SmartGolfCaddy

final class ModelsTests: XCTestCase {

    // MARK: HoleShots — паритет getHoleClubs

    func testResolvedClubsCanonical() {
        let shots = HoleShots(count: 2, clubs: ["Driver", "Putter"], legacyClub: nil, updatedAt: nil)
        XCTAssertEqual(shots.resolvedClubs, ["Driver", "Putter"])
    }

    func testResolvedClubsLegacy() {
        let shots = HoleShots(count: 3, clubs: [], legacyClub: "7i", updatedAt: nil)
        XCTAssertEqual(shots.resolvedClubs, ["7i", "7i", "7i"])
    }

    func testResolvedClubsUnknown() {
        let shots = HoleShots(count: 2, clubs: [], legacyClub: nil, updatedAt: nil)
        XCTAssertEqual(shots.resolvedClubs, ["Неизвестно", "Неизвестно"])
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
