import XCTest
@testable import SmartGolfCaddy

final class HomeViewModelTests: XCTestCase {
    private func activeRound(shotsOnHoles: [Int]) -> Round {
        var holes: [[String: Any]] = []
        for n in 1...9 {
            var shots: [String: [String: Any]] = [:]
            if shotsOnHoles.contains(n) {
                shots["u1"] = ["count": 4, "clubs": ["Driver", "7i", "PW", "Putter"]]
            }
            holes.append(["holeNumber": n, "par": 4, "distanceMeters": 360, "shots": shots])
        }
        return Round(id: "r", data: [
            "courseId": "c", "courseName": "Поле", "totalHoles": 9,
            "lobbyCode": "ABC234", "status": "active", "hostId": "u1",
            "players": ["u1": ["name": "А", "avatar": "", "totalScore": 0, "scoreDiff": 0]],
            "playerIds": ["u1"], "holes": holes,
            "startedAt": Date(), "createdAt": Date(),
        ])!
    }

    @MainActor
    func testResumeTargetsFirstUnplayedHole() {
        let round = activeRound(shotsOnHoles: [1, 2])
        XCTAssertEqual(HomeViewModel.resumeHoleNumber(round: round, userId: "u1"), 3)
    }

    @MainActor
    func testResumeAllPlayedTargetsLastHole() {
        let round = activeRound(shotsOnHoles: Array(1...9))
        XCTAssertEqual(HomeViewModel.resumeHoleNumber(round: round, userId: "u1"), 9)
    }

    @MainActor
    func testResumeSubtitleCountsPlayed() {
        let round = activeRound(shotsOnHoles: [1, 3, 5])
        XCTAssertEqual(HomeViewModel.resumeSubtitle(round: round, userId: "u1"), "Пройдено 3 из 9")
    }
}
