import XCTest
@testable import SmartGolfCaddy

final class RoundsServiceTests: XCTestCase {

    func testDefaultHoleParsShape() {
        XCTAssertEqual(Rounds.defaultHolePars(totalHoles: 9), [4, 3, 5, 4, 4, 3, 5, 4, 4])
        XCTAssertEqual(Rounds.defaultHolePars(totalHoles: 18).count, 18)
        XCTAssertEqual(Rounds.defaultHolePars(totalHoles: 18).reduce(0, +), 72)
    }

    func testBuildDefaultHolesDistances() {
        // База: par3=150, par5=480, par4=360; men ×1.0
        let holes = Rounds.buildDefaultHoles(totalHoles: 9, tee: .men)
        XCTAssertEqual(holes.count, 9)
        XCTAssertEqual(holes[0].par, 4); XCTAssertEqual(holes[0].distanceMeters, 360)
        XCTAssertEqual(holes[1].par, 3); XCTAssertEqual(holes[1].distanceMeters, 150)
        XCTAssertEqual(holes[2].par, 5); XCTAssertEqual(holes[2].distanceMeters, 480)
        XCTAssertEqual(holes[0].holeNumber, 1)
        XCTAssertTrue(holes.allSatisfy { $0.shots.isEmpty })
    }

    func testBuildDefaultHolesTeeMultiplier() {
        let ladies = Rounds.buildDefaultHoles(totalHoles: 9, tee: .ladies)
        XCTAssertEqual(ladies[1].distanceMeters, 120)  // 150 × 0.8
        let pro = Rounds.buildDefaultHoles(totalHoles: 9, tee: .pro)
        XCTAssertEqual(pro[2].distanceMeters, 528)     // 480 × 1.1
    }

    func testGenerateLobbyCode() {
        let allowed = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        for _ in 0..<50 {
            let code = Rounds.generateLobbyCode()
            XCTAssertEqual(code.count, 6)
            XCTAssertTrue(code.allSatisfy { allowed.contains($0) })
        }
    }

    func testHoleConfigFirestoreRoundTrip() {
        var config = Rounds.buildDefaultHoles(totalHoles: 9, tee: .men)[0]
        config.shots["u1"] = HoleShots(count: 2, clubs: ["Driver", "Putter"], legacyClub: nil, updatedAt: nil)
        let restored = HoleConfig(data: config.firestoreData)
        XCTAssertEqual(restored?.holeNumber, config.holeNumber)
        XCTAssertEqual(restored?.par, config.par)
        XCTAssertEqual(restored?.distanceMeters, config.distanceMeters)
        XCTAssertEqual(restored?.shots["u1"]?.resolvedClubs, ["Driver", "Putter"])
    }

    func testPlayerInfoFirestoreRoundTrip() {
        let info = PlayerInfo(name: "Джамбулат", avatar: "https://a.jpg", totalScore: 0, scoreDiff: 0, email: "x@y.z")
        let restored = PlayerInfo(data: info.firestoreData)
        XCTAssertEqual(restored, info)
        // email nil → ключ отсутствует
        let noEmail = PlayerInfo(name: "А", avatar: "", totalScore: 0, scoreDiff: 0, email: nil)
        XCTAssertNil(noEmail.firestoreData["email"])
    }
}
