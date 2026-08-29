import XCTest
@testable import SmartGolfCaddy

// Фикстуры строим через Round(id:data:) — тот же путь, что у прод-декода.
private func makeRound(
    holes: [[String: Any]],
    players: [String: [String: Any]] = ["u1": ["name": "А", "avatar": "", "totalScore": 0, "scoreDiff": 0]],
    playerIds: [String] = ["u1"],
    status: String = "active",
    playMode: String? = nil
) -> Round {
    var data: [String: Any] = [
        "courseId": "c", "courseName": "Поле", "totalHoles": holes.count,
        "lobbyCode": "ABC234", "status": status, "hostId": "u1",
        "players": players, "playerIds": playerIds,
        "holes": holes, "createdAt": Date(),
    ]
    if let playMode { data["playMode"] = playMode }
    return Round(id: "r", data: data)!
}

private func hole(_ n: Int, par: Int, shots: [String: [String: Any]] = [:]) -> [String: Any] {
    ["holeNumber": n, "par": par, "distanceMeters": 360, "shots": shots]
}

final class ScoringTests: XCTestCase {

    // MARK: playerTotals — считаются только лунки с ударами

    func testPlayerTotalsCountsOnlyPlayedHoles() {
        let round = makeRound(holes: [
            hole(1, par: 4, shots: ["u1": ["count": 5, "clubs": ["Driver", "7i", "7i", "PW", "Putter"]]]),
            hole(2, par: 3, shots: ["u1": ["count": 2, "clubs": ["7i", "Putter"]]]),
            hole(3, par: 5, shots: [:]),   // не сыграна — не входит ни в счёт, ни в пар
        ])
        let totals = Scoring.playerTotals(round: round, userId: "u1")
        XCTAssertEqual(totals.totalScore, 7)
        XCTAssertEqual(totals.scoreDiff, 0)   // 7 − (4+3)
    }

    func testPlayerTotalsEmpty() {
        let round = makeRound(holes: [hole(1, par: 4)])
        let totals = Scoring.playerTotals(round: round, userId: "u1")
        XCTAssertEqual(totals.totalScore, 0)
        XCTAssertEqual(totals.scoreDiff, 0)
    }

    // MARK: clubUsage — сортировка по убыванию, Clubs.unknownId исключён

    func testClubUsage() {
        let round = makeRound(holes: [
            hole(1, par: 4, shots: ["u1": ["count": 3, "clubs": ["Driver", "7i", "7i"]]]),
            hole(2, par: 4, shots: ["u1": ["count": 2, "clubs": [], "club": ""]]),  // resolvedClubs → Clubs.unknownId ×2
        ])
        let usage = Scoring.clubUsage(round: round, userId: "u1")
        XCTAssertEqual(usage.map(\.club), ["7i", "Driver"])
        XCTAssertEqual(usage[0].count, 2)
        XCTAssertEqual(usage[0].percent, 67)  // round(2/3×100)
        XCTAssertEqual(usage[1].percent, 33)
    }

    func testClubUsageTieBreaksByName() {
        let round = makeRound(holes: [
            hole(1, par: 4, shots: ["u1": ["count": 2, "clubs": ["SW", "Driver"]]]),
        ])
        let usage = Scoring.clubUsage(round: round, userId: "u1")
        XCTAssertEqual(usage.map(\.club), ["Driver", "SW"])  // count равен → по имени
    }

    func testClubUsageExcludesPenalty() {
        let round = makeRound(holes: [
            hole(1, par: 4, shots: ["u1": ["count": 3, "clubs": ["Driver", "Штраф", "Putter"]]]),
        ])
        let usage = Scoring.clubUsage(round: round, userId: "u1")
        XCTAssertEqual(usage.map(\.club).sorted(), ["Driver", "Putter"])
        XCTAssertEqual(usage.first?.percent, 50)  // из 2 не-штрафных
    }

    func testPenaltyConstantAndLabel() {
        XCTAssertEqual(Clubs.penaltyId, "Штраф")
        XCTAssertEqual(Clubs.label(for: Clubs.penaltyId, in: []), "Штраф")  // id вне abbrev → как есть
    }

    // MARK: leaderboard — без ударов тонут вниз, сортировка diff→total→имя

    func testLeaderboardSort() {
        let round = makeRound(
            holes: [
                hole(1, par: 4, shots: [
                    "a": ["count": 4, "clubs": ["Driver", "7i", "PW", "Putter"]],
                    "b": ["count": 3, "clubs": ["Driver", "PW", "Putter"]],
                ]),
            ],
            players: [
                "a": ["name": "Аня", "avatar": "", "totalScore": 0, "scoreDiff": 0],
                "b": ["name": "Борис", "avatar": "", "totalScore": 0, "scoreDiff": 0],
                "c": ["name": "Вера", "avatar": "", "totalScore": 0, "scoreDiff": 0],
            ],
            playerIds: ["a", "b", "c"]
        )
        let lb = Scoring.leaderboard(round: round)
        XCTAssertEqual(lb.map(\.uid), ["b", "a", "c"])  // c без ударов — внизу
        XCTAssertEqual(lb[0].thru, 1)
        XCTAssertEqual(lb[2].thru, 0)
    }

    func testLeaderboardTieBreakLocaleAware() {
        // Паритет с localeCompare веба: «андрей» сортируется раньше «Борис»,
        // хотя по код-пойнтам заглавная «Б» меньше строчной «а».
        let round = makeRound(
            holes: [
                hole(1, par: 4, shots: [
                    "x": ["count": 4, "clubs": ["7i", "7i", "PW", "Putter"]],
                    "y": ["count": 4, "clubs": ["7i", "7i", "PW", "Putter"]],
                ]),
            ],
            players: [
                "x": ["name": "андрей", "avatar": "", "totalScore": 0, "scoreDiff": 0],
                "y": ["name": "Борис", "avatar": "", "totalScore": 0, "scoreDiff": 0],
            ],
            playerIds: ["x", "y"]
        )
        XCTAssertEqual(Scoring.leaderboard(round: round).map(\.name), ["андрей", "Борис"])
    }

    // MARK: playerStats

    func testPlayerStats() {
        let r1 = makeRound(holes: [
            hole(1, par: 4, shots: ["u1": ["count": 3, "clubs": ["Driver", "PW", "Putter"]]]),  // birdie
            hole(2, par: 4, shots: ["u1": ["count": 6, "clubs": ["Driver", "7i", "7i", "PW", "Putter", "Putter"]]]),  // double
        ])
        let r2 = makeRound(holes: [
            hole(1, par: 4, shots: ["u1": ["count": 4, "clubs": ["Driver", "7i", "PW", "Putter"]]]),  // par
        ])
        let r3 = makeRound(holes: [hole(1, par: 4)])  // не играл — не считается
        let stats = Scoring.playerStats(rounds: [r1, r2, r3], userId: "u1")
        XCTAssertEqual(stats.roundsPlayed, 2)
        XCTAssertEqual(stats.totalShots, 13)
        XCTAssertEqual(stats.avgShots, 6.5)
        XCTAssertEqual(stats.bestScore, 4)
        XCTAssertEqual(stats.bestScoreDiff, 0)  // r2: 4−4=0 лучше, чем r1: 9−8=1
        XCTAssertEqual(stats.holeStats.birdie, 1)
        XCTAssertEqual(stats.holeStats.double, 1)
        XCTAssertEqual(stats.holeStats.par, 1)
        XCTAssertEqual(stats.totalHolesPlayed, 3)
    }

    // MARK: handicap — null при <3 раундов; best 8 из 20 × 0.96

    func testHandicapNeedsThreeRounds() {
        let r = makeRound(holes: [hole(1, par: 4, shots: ["u1": ["count": 5, "clubs": ["Driver", "7i", "7i", "PW", "Putter"]]])], status: "finished")
        XCTAssertNil(Scoring.handicap(rounds: [r, r], userId: "u1"))
    }

    func testHandicapAveragesBest() {
        // Три finished-раунда c diff: +1, +1, +4 → best 3 = все, avg=2.0, ×0.96=1.92 → 1.9
        func finished(diffOverPar: Int) -> Round {
            makeRound(holes: [hole(1, par: 4, shots: ["u1": ["count": 4 + diffOverPar, "clubs": Array(repeating: "7i", count: 4 + diffOverPar)]])], status: "finished")
        }
        let result = Scoring.handicap(rounds: [finished(diffOverPar: 1), finished(diffOverPar: 1), finished(diffOverPar: 4)], userId: "u1")
        XCTAssertEqual(result?.index, 1.9)
        XCTAssertEqual(result?.basedOnRounds, 3)
        XCTAssertEqual(result?.bestUsed, 3)
    }

    func testHandicapIgnoresUnfinished() {
        let active = makeRound(holes: [hole(1, par: 4, shots: ["u1": ["count": 5, "clubs": ["7i"]]])], status: "active")
        XCTAssertNil(Scoring.handicap(rounds: [active, active, active], userId: "u1"))
    }

    // MARK: match play

    func testMatchPlayLabels() {
        // 3 лунки: a выигрывает 1-ю и 2-ю, 3-я не сыграна → 2&1 (closed)
        let round = makeRound(
            holes: [
                hole(1, par: 4, shots: ["a": ["count": 3, "clubs": ["7i", "PW", "Putter"]], "b": ["count": 4, "clubs": ["7i", "7i", "PW", "Putter"]]]),
                hole(2, par: 4, shots: ["a": ["count": 3, "clubs": ["7i", "PW", "Putter"]], "b": ["count": 5, "clubs": ["7i", "7i", "7i", "PW", "Putter"]]]),
                hole(3, par: 4),
            ],
            players: [
                "a": ["name": "Аня", "avatar": "", "totalScore": 0, "scoreDiff": 0],
                "b": ["name": "Борис", "avatar": "", "totalScore": 0, "scoreDiff": 0],
            ],
            playerIds: ["a", "b"], playMode: "match"
        )
        let st = Scoring.matchPlayStatus(round: round, uidA: "a", uidB: "b")
        XCTAssertEqual(st.leaderUid, "a")
        XCTAssertEqual(st.delta, 2)
        XCTAssertEqual(st.holesRemaining, 1)
        XCTAssertTrue(st.closed)
        XCTAssertEqual(st.label, "2&1")
    }

    func testMatchPlayAllSquareAndFinished() {
        let round = makeRound(
            holes: [hole(1, par: 4, shots: ["a": ["count": 4, "clubs": ["7i", "7i", "PW", "Putter"]], "b": ["count": 4, "clubs": ["7i", "7i", "PW", "Putter"]]])],
            players: [
                "a": ["name": "Аня", "avatar": "", "totalScore": 0, "scoreDiff": 0],
                "b": ["name": "Борис", "avatar": "", "totalScore": 0, "scoreDiff": 0],
            ],
            playerIds: ["a", "b"], playMode: "match"
        )
        XCTAssertEqual(Scoring.matchPlayStatus(round: round, uidA: "a", uidB: "b").label, "AS")
    }

    func testMatchPlayMidRoundLabels() {
        // 3 лунки, сыграна 1: A выиграл → "1 UP" (не закрыто); ничья → "AS"
        func round(aCount: Int, bCount: Int) -> Round {
            makeRound(
                holes: [
                    hole(1, par: 4, shots: [
                        "a": ["count": aCount, "clubs": Array(repeating: "7i", count: aCount)],
                        "b": ["count": bCount, "clubs": Array(repeating: "7i", count: bCount)],
                    ]),
                    hole(2, par: 4), hole(3, par: 4),
                ],
                players: [
                    "a": ["name": "А", "avatar": "", "totalScore": 0, "scoreDiff": 0],
                    "b": ["name": "Б", "avatar": "", "totalScore": 0, "scoreDiff": 0],
                ],
                playerIds: ["a", "b"], playMode: "match"
            )
        }
        XCTAssertEqual(Scoring.matchPlayStatus(round: round(aCount: 3, bCount: 4), uidA: "a", uidB: "b").label, "1 UP")
        XCTAssertEqual(Scoring.matchPlayStatus(round: round(aCount: 4, bCount: 4), uidA: "a", uidB: "b").label, "AS")
    }

    func testLeaderboardTotalScoreTieBreak() {
        // Равный diff, разный total: меньше ударов — выше
        let round = makeRound(
            holes: [
                hole(1, par: 4, shots: ["a": ["count": 4, "clubs": ["7i", "7i", "PW", "Putter"]]]),
                hole(2, par: 3, shots: ["b": ["count": 3, "clubs": ["7i", "PW", "Putter"]]]),
            ],
            players: [
                "a": ["name": "А", "avatar": "", "totalScore": 0, "scoreDiff": 0],
                "b": ["name": "Б", "avatar": "", "totalScore": 0, "scoreDiff": 0],
            ],
            playerIds: ["a", "b"]
        )
        XCTAssertEqual(Scoring.leaderboard(round: round).map(\.uid), ["b", "a"])
    }

    func testClubUsageAcrossRounds() {
        let r1 = makeRound(holes: [hole(1, par: 4, shots: ["u1": ["count": 1, "clubs": ["Driver"]]])])
        let r2 = makeRound(holes: [hole(1, par: 4, shots: ["u1": ["count": 2, "clubs": ["Driver", "PW"]]])])
        let usage = Scoring.clubUsage(rounds: [r1, r2], userId: "u1")
        XCTAssertEqual(usage.first?.club, "Driver")
        XCTAssertEqual(usage.first?.count, 2)
        XCTAssertEqual(usage.first?.percent, 67)
    }

    func testClubUsageAveragesDistances() {
        let round = makeRound(holes: [
            hole(1, par: 4, shots: ["u1": ["count": 3, "clubs": ["Driver", "Driver", "Putter"],
                                           "distances": [200, 220, 0]]]),
        ])
        let usage = Scoring.clubUsage(round: round, userId: "u1")
        let driver = usage.first { $0.club == "Driver" }
        XCTAssertEqual(driver?.avgDistanceMeters, 210)
        XCTAssertEqual(usage.first { $0.club == "Putter" }?.avgDistanceMeters, 0)
    }

    // MARK: TeeColor labels

    func testTeeLabels() {
        // T4: label/teeDescription are locale-dependent now — compare
        // against the current-locale string, not a hardcoded Russian one.
        XCTAssertEqual(TeeColor.men.label, AppLocaleStore.strings.common.tee.men.label)
        XCTAssertEqual(TeeColor.pro.bgHex, "#0A3010")
        XCTAssertEqual(TeeColor.ladies.textHex, "#FFFFFF")
        XCTAssertEqual(TeeColor.senior.teeDescription, AppLocaleStore.strings.common.tee.senior.description)
    }
}
