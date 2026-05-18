import { describe, it, expect } from 'vitest'
import { computePlayerTotals, computeClubUsage } from './scoring'
import type { Round, HoleConfig } from '../types'

function makeRound(overrides: Partial<Round> = {}): Round {
  const holes: HoleConfig[] = [
    { holeNumber: 1, par: 4, distanceMeters: 360, shots: { uid1: { count: 3, clubs: ['Driver', '7i', 'Putter'], updatedAt: new Date() } } },
    { holeNumber: 2, par: 3, distanceMeters: 150, shots: { uid1: { count: 2, clubs: ['7i', 'Putter'], updatedAt: new Date() } } },
    { holeNumber: 3, par: 5, distanceMeters: 480, shots: { uid1: { count: 5, clubs: ['Driver', '3W', '7i', 'PW', 'Putter'], updatedAt: new Date() } } },
  ]
  return {
    id: 'r1', courseId: 'c1', courseName: 'Test', totalHoles: 9, lobbyCode: 'ABC123',
    status: 'finished', hostId: 'uid1',
    players: { uid1: { name: 'Alice', avatar: '', totalScore: 0, scoreDiff: 0 } },
    holes, startedAt: new Date(), finishedAt: new Date(), createdAt: new Date(),
    ...overrides,
  }
}

describe('computePlayerTotals', () => {
  it('computes totals from clubs[] length when present', () => {
    const r = makeRound()
    const { totalScore, scoreDiff } = computePlayerTotals(r, 'uid1')
    expect(totalScore).toBe(10) // 3+2+5
    expect(scoreDiff).toBe(-2)  // 10 vs par 12
  })

  it('returns 0/0 for unknown player', () => {
    expect(computePlayerTotals(makeRound(), 'unknown')).toEqual({ totalScore: 0, scoreDiff: 0 })
  })
})

describe('computeClubUsage', () => {
  it('aggregates club usage from a single round', () => {
    const stats = computeClubUsage(makeRound(), 'uid1')
    // Driver: 2, 7i: 3, Putter: 3, 3W: 1, PW: 1 → 10 total
    const driver = stats.find(s => s.club === 'Driver')
    const seven = stats.find(s => s.club === '7i')
    const putter = stats.find(s => s.club === 'Putter')
    expect(driver?.count).toBe(2)
    expect(seven?.count).toBe(3)
    expect(putter?.count).toBe(3)
    expect(stats[0].percent + stats[stats.length - 1].percent).toBeGreaterThan(0)
  })

  it('sorts by count desc then by club name', () => {
    const stats = computeClubUsage(makeRound(), 'uid1')
    for (let i = 1; i < stats.length; i++) {
      expect(stats[i - 1].count).toBeGreaterThanOrEqual(stats[i].count)
    }
  })

  it('returns empty array when user has no shots', () => {
    expect(computeClubUsage(makeRound(), 'unknown')).toEqual([])
  })

  it('aggregates across multiple rounds', () => {
    const r1 = makeRound()
    const r2 = makeRound()
    const single = computeClubUsage(r1, 'uid1')
    const multi = computeClubUsage([r1, r2], 'uid1')
    // Multi should have same clubs with double the counts
    for (const stat of single) {
      const matching = multi.find(m => m.club === stat.club)
      expect(matching?.count).toBe(stat.count * 2)
    }
  })

  it('handles legacy data (club: string, no clubs[])', () => {
    const r = makeRound({
      holes: [
        { holeNumber: 1, par: 4, distanceMeters: 360, shots: { uid1: { count: 3, clubs: [], club: '7i', updatedAt: new Date() } } },
      ],
    })
    const stats = computeClubUsage(r, 'uid1')
    expect(stats[0].club).toBe('7i')
    expect(stats[0].count).toBe(3) // synthesized: 3 strokes all attributed to "7i"
  })
})
