import Foundation

struct PlayerTotals: Equatable {
    var totalScore: Int
    var scoreDiff: Int
}

struct ClubStat: Equatable, Identifiable {
    let club: String
    let count: Int
    let percent: Int
    var id: String { club }
}

struct LeaderboardEntry: Equatable, Identifiable {
    let uid: String
    let name: String
    let avatar: String
    let totalScore: Int
    let scoreDiff: Int
    let thru: Int
    var id: String { uid }
}

struct HoleResultStats: Equatable {
    var eagle = 0, birdie = 0, par = 0, bogey = 0, double = 0, worse = 0
}

struct PlayerStats: Equatable {
    var roundsPlayed: Int
    var totalShots: Int
    var avgShots: Double
    var bestScore: Int?
    var bestScoreDiff: Int?
    var holeStats: HoleResultStats
    var totalHolesPlayed: Int
}

struct HandicapResult: Equatable {
    var index: Double
    var basedOnRounds: Int
    var bestUsed: Int
}

struct MatchPlayStatus: Equatable {
    var leaderUid: String?
    var trailerUid: String?
    var holesPlayed: Int
    var holesRemaining: Int
    var delta: Int
    var label: String
    var closed: Bool
}

enum Scoring {

    static func playerTotals(round: Round, userId: String) -> PlayerTotals {
        var totalScore = 0
        var totalPar = 0
        var hasAnyShots = false
        for hole in round.holes {
            let count = hole.shots[userId]?.count ?? 0
            if count > 0 {
                hasAnyShots = true
                totalScore += count
                totalPar += hole.par
            }
        }
        if !hasAnyShots { return PlayerTotals(totalScore: 0, scoreDiff: 0) }
        return PlayerTotals(totalScore: totalScore, scoreDiff: totalScore - totalPar)
    }

    static func clubUsage(round: Round, userId: String) -> [ClubStat] {
        clubUsage(rounds: [round], userId: userId)
    }

    static func clubUsage(rounds: [Round], userId: String) -> [ClubStat] {
        var counts: [String: Int] = [:]
        var total = 0
        for round in rounds {
            for hole in round.holes {
                for club in hole.shots[userId]?.resolvedClubs ?? [] {
                    if club == "Неизвестно" { continue }
                    counts[club, default: 0] += 1
                    total += 1
                }
            }
        }
        if total == 0 { return [] }
        return counts
            .map { club, count in
                ClubStat(club: club, count: count,
                         percent: Int((Double(count) / Double(total) * 100).rounded()))
            }
            .sorted { a, b in
                if a.count != b.count { return a.count > b.count }
                return a.club < b.club
            }
    }

    static func leaderboard(round: Round) -> [LeaderboardEntry] {
        var entries: [LeaderboardEntry] = []
        for uid in round.playerIds {
            guard let player = round.players[uid] else { continue }
            let totals = playerTotals(round: round, userId: uid)
            let thru = round.holes.filter { ($0.shots[uid]?.count ?? 0) > 0 }.count
            entries.append(LeaderboardEntry(
                uid: uid, name: player.name, avatar: player.avatar,
                totalScore: totals.totalScore, scoreDiff: totals.scoreDiff, thru: thru
            ))
        }
        return entries.sorted { a, b in
            if a.thru == 0 && b.thru > 0 { return false }
            if b.thru == 0 && a.thru > 0 { return true }
            if a.scoreDiff != b.scoreDiff { return a.scoreDiff < b.scoreDiff }
            if a.totalScore != b.totalScore { return a.totalScore < b.totalScore }
            return a.name < b.name
        }
    }

    static func playerStats(rounds: [Round], userId: String) -> PlayerStats {
        var totalShots = 0
        var bestScore: Int?
        var bestScoreDiff: Int?
        var roundsPlayed = 0
        var totalHolesPlayed = 0
        var holeStats = HoleResultStats()

        for round in rounds {
            let totals = playerTotals(round: round, userId: userId)
            if totals.totalScore == 0 { continue }
            roundsPlayed += 1
            totalShots += totals.totalScore
            if bestScore == nil || totals.totalScore < bestScore! { bestScore = totals.totalScore }
            if bestScoreDiff == nil || totals.scoreDiff < bestScoreDiff! { bestScoreDiff = totals.scoreDiff }

            for hole in round.holes {
                let count = hole.shots[userId]?.count ?? 0
                if count == 0 { continue }
                totalHolesPlayed += 1
                let delta = count - hole.par
                if delta <= -2 { holeStats.eagle += 1 }
                else if delta == -1 { holeStats.birdie += 1 }
                else if delta == 0 { holeStats.par += 1 }
                else if delta == 1 { holeStats.bogey += 1 }
                else if delta == 2 { holeStats.double += 1 }
                else { holeStats.worse += 1 }
            }
        }

        let avgShots = roundsPlayed > 0
            ? (Double(totalShots) / Double(roundsPlayed) * 100).rounded() / 100
            : 0
        return PlayerStats(
            roundsPlayed: roundsPlayed, totalShots: totalShots, avgShots: avgShots,
            bestScore: bestScore, bestScoreDiff: bestScoreDiff,
            holeStats: holeStats, totalHolesPlayed: totalHolesPlayed
        )
    }

    static func handicap(rounds: [Round], userId: String) -> HandicapResult? {
        var diffs: [Int] = []
        for round in rounds {
            guard round.status == .finished else { continue }
            let totals = playerTotals(round: round, userId: userId)
            if totals.totalScore == 0 { continue }
            diffs.append(totals.scoreDiff)
        }
        if diffs.count < 3 { return nil }
        let recent = Array(diffs.prefix(20))
        let bestN = min(8, recent.count)
        let best = recent.sorted().prefix(bestN)
        let avg = Double(best.reduce(0, +)) / Double(bestN)
        let index = (avg * 0.96 * 10).rounded() / 10
        return HandicapResult(index: index, basedOnRounds: recent.count, bestUsed: bestN)
    }

    static func matchPlayStatus(round: Round, uidA: String, uidB: String) -> MatchPlayStatus {
        var aUp = 0, bUp = 0, holesPlayed = 0
        for hole in round.holes {
            let aCount = hole.shots[uidA]?.count ?? 0
            let bCount = hole.shots[uidB]?.count ?? 0
            if aCount == 0 || bCount == 0 { continue }
            holesPlayed += 1
            if aCount < bCount { aUp += 1 }
            else if bCount < aCount { bUp += 1 }
        }
        let delta = abs(aUp - bUp)
        let holesRemaining = round.holes.count - holesPlayed
        let closed = delta > holesRemaining
        let leaderUid = aUp > bUp ? uidA : (bUp > aUp ? uidB : nil)
        let trailerUid = leaderUid == uidA ? uidB : (leaderUid == uidB ? uidA : nil)

        let label: String
        if round.status == .finished || holesRemaining == 0 {
            label = delta == 0 ? "AS" : "\(delta) UP"
        } else if closed {
            label = "\(delta)&\(holesRemaining)"
        } else if delta == 0 {
            label = "AS"
        } else {
            label = "\(delta) UP"
        }
        return MatchPlayStatus(
            leaderUid: leaderUid, trailerUid: trailerUid,
            holesPlayed: holesPlayed, holesRemaining: holesRemaining,
            delta: delta, label: label, closed: closed
        )
    }
}
