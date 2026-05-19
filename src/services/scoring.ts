import type { Round } from '../types'
import { getHoleClubs } from '../types'

// ============================================================================
// Per-round computations
// ============================================================================

export function computePlayerTotals(
  round: Round,
  userId: string,
): { totalScore: number; scoreDiff: number } {
  let totalScore = 0
  let totalPar = 0
  let hasAnyShots = false
  for (const hole of round.holes) {
    const count = hole.shots[userId]?.count ?? 0
    if (count > 0) {
      hasAnyShots = true
      totalScore += count
      totalPar += hole.par
    }
  }
  if (!hasAnyShots) return { totalScore: 0, scoreDiff: 0 }
  return { totalScore, scoreDiff: totalScore - totalPar }
}

export interface ClubStat {
  club: string
  count: number
  percent: number
}

// Aggregate club usage for a user across one round or multiple rounds.
// Returns clubs sorted by usage descending. Excludes 'Неизвестно' from results.
export function computeClubUsage(
  source: Round | Round[],
  userId: string,
): ClubStat[] {
  const rounds = Array.isArray(source) ? source : [source]
  const counts = new Map<string, number>()
  let total = 0

  for (const round of rounds) {
    for (const hole of round.holes) {
      const clubs = getHoleClubs(hole.shots[userId])
      for (const club of clubs) {
        if (club === 'Неизвестно') continue
        counts.set(club, (counts.get(club) ?? 0) + 1)
        total += 1
      }
    }
  }

  if (total === 0) return []

  return Array.from(counts.entries())
    .map(([club, count]) => ({
      club,
      count,
      percent: Math.round((count / total) * 100),
    }))
    .sort((a, b) => b.count - a.count || a.club.localeCompare(b.club))
}

// ============================================================================
// Aggregate player stats (GameBook-style summary)
// ============================================================================

export interface HoleResultStats {
  eagle: number   // delta <= -2 (eagle and better)
  birdie: number  // delta === -1
  par: number     // delta === 0
  bogey: number   // delta === 1
  double: number  // delta === 2
  worse: number   // delta >= 3
}

export interface PlayerStats {
  roundsPlayed: number
  totalShots: number
  avgShots: number            // average shots per round, rounded to .01
  bestScore: number | null    // lowest totalScore across all rounds (null if no rounds)
  bestScoreDiff: number | null
  holeStats: HoleResultStats
  totalHolesPlayed: number    // sum of holes where user has shots
}

function emptyHoleStats(): HoleResultStats {
  return { eagle: 0, birdie: 0, par: 0, bogey: 0, double: 0, worse: 0 }
}

export function computePlayerStats(rounds: Round[], userId: string): PlayerStats {
  let totalShots = 0
  let bestScore: number | null = null
  let bestScoreDiff: number | null = null
  let roundsPlayed = 0
  let totalHolesPlayed = 0
  const holeStats = emptyHoleStats()

  for (const round of rounds) {
    const totals = computePlayerTotals(round, userId)
    if (totals.totalScore === 0) continue // user didn't play this round
    roundsPlayed += 1
    totalShots += totals.totalScore
    if (bestScore == null || totals.totalScore < bestScore) bestScore = totals.totalScore
    if (bestScoreDiff == null || totals.scoreDiff < bestScoreDiff) bestScoreDiff = totals.scoreDiff

    for (const hole of round.holes) {
      const count = hole.shots[userId]?.count ?? 0
      if (count === 0) continue
      totalHolesPlayed += 1
      const delta = count - hole.par
      if (delta <= -2) holeStats.eagle += 1
      else if (delta === -1) holeStats.birdie += 1
      else if (delta === 0) holeStats.par += 1
      else if (delta === 1) holeStats.bogey += 1
      else if (delta === 2) holeStats.double += 1
      else holeStats.worse += 1
    }
  }

  const avgShots = roundsPlayed > 0 ? Math.round((totalShots / roundsPlayed) * 100) / 100 : 0

  return {
    roundsPlayed,
    totalShots,
    avgShots,
    bestScore,
    bestScoreDiff,
    holeStats,
    totalHolesPlayed,
  }
}

// ============================================================================
// Simplified WHS handicap
// ============================================================================
//
// Real WHS uses course rating + slope (we don't have those for our places).
// Simplified version:
//   score differential = totalScore - totalPar (for holes the user played)
//   take best 8 of the last 20 finished rounds
//   handicap index ≈ average × 0.96
//
// Returns null when fewer than 3 rounds — not enough data to be meaningful.

export interface HandicapResult {
  index: number               // rounded to 1 decimal
  basedOnRounds: number       // how many rounds counted (≤ 20)
  bestUsed: number            // how many used in the average (8 if available, else `basedOnRounds`)
}

export function computeHandicap(rounds: Round[], userId: string): HandicapResult | null {
  // Use only finished rounds with actual shots recorded by this user.
  const diffs: number[] = []
  for (const round of rounds) {
    if (round.status !== 'finished') continue
    const { totalScore, scoreDiff } = computePlayerTotals(round, userId)
    if (totalScore === 0) continue
    diffs.push(scoreDiff)
  }

  if (diffs.length < 3) return null

  const recent = diffs.slice(0, 20)              // assume rounds passed in newest-first; trims older
  const bestN = Math.min(8, recent.length)
  const best = [...recent].sort((a, b) => a - b).slice(0, bestN)
  const avg = best.reduce((s, d) => s + d, 0) / bestN
  const index = Math.round(avg * 0.96 * 10) / 10

  return { index, basedOnRounds: recent.length, bestUsed: bestN }
}

// ============================================================================
// Match play (head-to-head, 2 players)
// ============================================================================

export interface MatchPlayStatus {
  leaderUid: string | null    // null when tied
  trailerUid: string | null   // null when tied
  holesPlayed: number
  holesRemaining: number
  delta: number               // |leader holes won - trailer holes won|
  /**
   * 'AS' when tied (all square)
   * 'N UP' when leader has more holes won AND match is still open
   * 'N&M'  when leader has clinched: leader is N up with M to play (N > M)
   * 'FINAL' when round is over (all holes played); delta is the final margin
   */
  label: string
  /** True if delta > holesRemaining — match is mathematically decided */
  closed: boolean
}

export function computeMatchPlayStatus(
  round: Round,
  uidA: string,
  uidB: string,
): MatchPlayStatus {
  let aUp = 0
  let bUp = 0
  let holesPlayed = 0

  for (const hole of round.holes) {
    const aCount = hole.shots[uidA]?.count ?? 0
    const bCount = hole.shots[uidB]?.count ?? 0
    // Both players must have recorded shots for the hole to count as played.
    if (aCount === 0 || bCount === 0) continue
    holesPlayed += 1
    if (aCount < bCount) aUp += 1
    else if (bCount < aCount) bUp += 1
    // ties don't change the score
  }

  const delta = Math.abs(aUp - bUp)
  const holesRemaining = round.holes.length - holesPlayed
  const closed = delta > holesRemaining
  const leaderUid = aUp > bUp ? uidA : bUp > aUp ? uidB : null
  const trailerUid = leaderUid === uidA ? uidB : leaderUid === uidB ? uidA : null

  let label: string
  if (round.status === 'finished' || holesRemaining === 0) {
    label = delta === 0 ? 'AS' : `${delta} UP`
  } else if (closed) {
    label = `${delta}&${holesRemaining}`
  } else if (delta === 0) {
    label = 'AS'
  } else {
    label = `${delta} UP`
  }

  return { leaderUid, trailerUid, holesPlayed, holesRemaining, delta, label, closed }
}

// ============================================================================
// Live leaderboard during a round
// ============================================================================

export interface LeaderboardEntry {
  uid: string
  name: string
  avatar: string
  totalScore: number
  scoreDiff: number
  thru: number          // number of holes with at least one shot recorded
}

export function computeLeaderboard(round: Round): LeaderboardEntry[] {
  const entries: LeaderboardEntry[] = []
  for (const uid of round.playerIds) {
    const player = round.players[uid]
    if (!player) continue
    const { totalScore, scoreDiff } = computePlayerTotals(round, uid)
    let thru = 0
    for (const hole of round.holes) {
      if ((hole.shots[uid]?.count ?? 0) > 0) thru += 1
    }
    entries.push({
      uid,
      name: player.name,
      avatar: player.avatar,
      totalScore,
      scoreDiff,
      thru,
    })
  }

  // Sort: by scoreDiff asc, then totalShots asc, then name. Players with no
  // recorded shots (thru === 0) sink to the bottom even if their scoreDiff is 0.
  return entries.sort((a, b) => {
    if (a.thru === 0 && b.thru > 0) return 1
    if (b.thru === 0 && a.thru > 0) return -1
    if (a.scoreDiff !== b.scoreDiff) return a.scoreDiff - b.scoreDiff
    if (a.totalScore !== b.totalScore) return a.totalScore - b.totalScore
    return a.name.localeCompare(b.name)
  })
}
