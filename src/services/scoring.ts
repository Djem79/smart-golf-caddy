import type { Round } from '../types'
import { getHoleClubs } from '../types'

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
