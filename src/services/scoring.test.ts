import { describe, it, expect } from 'vitest'
import { computePlayerTotals, computeClubUsage, computePlayerStats, computeHandicap, computeMatchPlayStatus, computeLeaderboard } from './scoring'
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
    playerIds: ['uid1'],
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

describe('computePlayerStats', () => {
  it('returns zeros for empty rounds list', () => {
    const s = computePlayerStats([], 'uid1')
    expect(s.roundsPlayed).toBe(0)
    expect(s.totalShots).toBe(0)
    expect(s.bestScore).toBeNull()
    expect(s.bestScoreDiff).toBeNull()
  })

  it('aggregates totals across rounds', () => {
    // Round 1: shots 3+2+5 = 10 (par 12, diff -2)
    // Round 2: shots 4+4+6 = 14 (par 12, diff +2)
    const r1 = makeRound()
    const r2 = makeRound({
      id: 'r2',
      holes: [
        { holeNumber: 1, par: 4, distanceMeters: 360, shots: { uid1: { count: 4, clubs: ['Driver', '7i', 'PW', 'Putter'], updatedAt: new Date() } } },
        { holeNumber: 2, par: 3, distanceMeters: 150, shots: { uid1: { count: 4, clubs: ['7i', 'PW', 'PW', 'Putter'], updatedAt: new Date() } } },
        { holeNumber: 3, par: 5, distanceMeters: 480, shots: { uid1: { count: 6, clubs: ['Driver', '3W', '7i', '8i', 'PW', 'Putter'], updatedAt: new Date() } } },
      ],
    })
    const s = computePlayerStats([r1, r2], 'uid1')
    expect(s.roundsPlayed).toBe(2)
    expect(s.totalShots).toBe(24)
    expect(s.avgShots).toBe(12)
    expect(s.bestScore).toBe(10)
    expect(s.bestScoreDiff).toBe(-2)
    expect(s.totalHolesPlayed).toBe(6)
  })

  it('classifies hole results correctly', () => {
    // Round: par 4 hole with 2 (eagle), par 3 hole with 2 (birdie), par 5 hole with 5 (par)
    const r = makeRound({
      holes: [
        { holeNumber: 1, par: 4, distanceMeters: 360, shots: { uid1: { count: 2, clubs: ['Driver', 'Putter'], updatedAt: new Date() } } },
        { holeNumber: 2, par: 3, distanceMeters: 150, shots: { uid1: { count: 2, clubs: ['7i', 'Putter'], updatedAt: new Date() } } },
        { holeNumber: 3, par: 5, distanceMeters: 480, shots: { uid1: { count: 5, clubs: ['Driver', '3W', '7i', 'PW', 'Putter'], updatedAt: new Date() } } },
      ],
    })
    const s = computePlayerStats([r], 'uid1')
    expect(s.holeStats.eagle).toBe(1)
    expect(s.holeStats.birdie).toBe(1)
    expect(s.holeStats.par).toBe(1)
    expect(s.holeStats.bogey).toBe(0)
  })

  it('skips rounds the user didn\'t play in', () => {
    const r1 = makeRound()
    // r2: only uid2 has shots, uid1 has no recorded shots in any hole
    const r2 = makeRound({
      id: 'r2',
      players: { uid2: { name: 'Bob', avatar: '', totalScore: 0, scoreDiff: 0 } },
      playerIds: ['uid2'],
      holes: [
        { holeNumber: 1, par: 4, distanceMeters: 360, shots: { uid2: { count: 3, clubs: [], updatedAt: new Date() } } },
        { holeNumber: 2, par: 3, distanceMeters: 150, shots: { uid2: { count: 3, clubs: [], updatedAt: new Date() } } },
        { holeNumber: 3, par: 5, distanceMeters: 480, shots: { uid2: { count: 5, clubs: [], updatedAt: new Date() } } },
      ],
    })
    const s = computePlayerStats([r1, r2], 'uid1')
    expect(s.roundsPlayed).toBe(1)
  })
})

describe('computeHandicap', () => {
  function makeFinishedRound(scoreDiff: number, idSuffix: string): Round {
    // Construct a round where uid1's score == par + scoreDiff.
    // 3 holes, par 12 total. Distribute extra shots into hole 1.
    const baseShots = [3, 3, 5] // par-totals are 4+3+5=12, so 3+3+5=11 (-1 diff)
    const extra = scoreDiff + 1 // adjust hole 1 to reach desired diff
    const shots = [baseShots[0] + extra, baseShots[1], baseShots[2]]
    return {
      id: `r-${idSuffix}`, courseId: 'c', courseName: 'Test',
      totalHoles: 9, lobbyCode: 'X', status: 'finished', hostId: 'uid1',
      players: { uid1: { name: 'A', avatar: '', totalScore: 0, scoreDiff: 0 } },
      playerIds: ['uid1'],
      holes: [
        { holeNumber: 1, par: 4, distanceMeters: 360, shots: { uid1: { count: shots[0], clubs: [], updatedAt: new Date() } } },
        { holeNumber: 2, par: 3, distanceMeters: 150, shots: { uid1: { count: shots[1], clubs: [], updatedAt: new Date() } } },
        { holeNumber: 3, par: 5, distanceMeters: 480, shots: { uid1: { count: shots[2], clubs: [], updatedAt: new Date() } } },
      ],
      startedAt: new Date(), finishedAt: new Date(), createdAt: new Date(),
    }
  }

  it('returns null when fewer than 3 finished rounds', () => {
    expect(computeHandicap([], 'uid1')).toBeNull()
    expect(computeHandicap([makeFinishedRound(5, '1'), makeFinishedRound(7, '2')], 'uid1')).toBeNull()
  })

  it('uses the best of available rounds × 0.96', () => {
    // 5 rounds with diffs: 10, 6, 8, 4, 12. Best of all 5 (since < 8): 4, 6, 8, 10, 12.
    // Average = 8. × 0.96 = 7.68 → rounds to 7.7
    const rounds = [10, 6, 8, 4, 12].map((d, i) => makeFinishedRound(d, String(i)))
    const result = computeHandicap(rounds, 'uid1')
    expect(result?.index).toBeCloseTo(7.7, 1)
    expect(result?.basedOnRounds).toBe(5)
    expect(result?.bestUsed).toBe(5)
  })

  it('uses best 8 when ≥ 8 rounds are available', () => {
    // 10 rounds with diffs 0..9. Best 8 = 0..7. Average = 3.5. × 0.96 = 3.36 → 3.4
    const rounds = Array.from({ length: 10 }, (_, i) => makeFinishedRound(i, String(i)))
    const result = computeHandicap(rounds, 'uid1')
    expect(result?.bestUsed).toBe(8)
    expect(result?.index).toBeCloseTo(3.4, 1)
  })

  it('skips non-finished rounds', () => {
    const active = makeFinishedRound(5, '1')
    active.status = 'active'
    const rounds = [active, makeFinishedRound(10, '2'), makeFinishedRound(8, '3'), makeFinishedRound(6, '4')]
    const result = computeHandicap(rounds, 'uid1')
    // Only 3 finished rounds count (excluding active)
    expect(result?.basedOnRounds).toBe(3)
  })
})

describe('computeMatchPlayStatus', () => {
  function makeMatch(holes: Array<{ par: number; a: number; b: number }>, status: Round['status'] = 'active'): Round {
    // The function counts holesRemaining = round.holes.length - holesPlayed,
    // so make sure the holes array matches totalHoles. Pad with empty holes
    // (no shots) when the test only specifies a few played holes.
    const totalHoles = 9 as const
    const padded = [
      ...holes,
      ...Array.from({ length: Math.max(0, totalHoles - holes.length) }, () => ({ par: 4, a: 0, b: 0 })),
    ]
    return {
      id: 'm', courseId: 'c', courseName: 'T', totalHoles, lobbyCode: 'X', status,
      hostId: 'a',
      players: {
        a: { name: 'Alice', avatar: '', totalScore: 0, scoreDiff: 0 },
        b: { name: 'Bob',   avatar: '', totalScore: 0, scoreDiff: 0 },
      },
      playerIds: ['a', 'b'],
      holes: padded.map((h, i) => ({
        holeNumber: i + 1, par: h.par as 3 | 4 | 5, distanceMeters: 200,
        shots: {
          ...(h.a > 0 ? { a: { count: h.a, clubs: [], updatedAt: new Date() } } : {}),
          ...(h.b > 0 ? { b: { count: h.b, clubs: [], updatedAt: new Date() } } : {}),
        },
      })),
      startedAt: new Date(), finishedAt: null, createdAt: new Date(),
    }
  }

  it('returns AS when no holes played', () => {
    const r = makeMatch([{ par: 4, a: 0, b: 0 }, { par: 4, a: 0, b: 0 }])
    const s = computeMatchPlayStatus(r, 'a', 'b')
    expect(s.holesPlayed).toBe(0)
    expect(s.label).toBe('AS')
    expect(s.leaderUid).toBeNull()
  })

  it('marks leader 1 UP after one winning hole', () => {
    const r = makeMatch([{ par: 4, a: 3, b: 4 }])
    const s = computeMatchPlayStatus(r, 'a', 'b')
    expect(s.leaderUid).toBe('a')
    expect(s.delta).toBe(1)
    expect(s.label).toBe('1 UP')
  })

  it('uses N&M label when leader has clinched (9-hole match, 4&3)', () => {
    // 6 holes played out of 9 total. Alice wins 4, halves 2 → 4 up.
    // 3 remaining; 4 > 3 → clinched 4&3
    const r = makeMatch([
      { par: 4, a: 3, b: 4 }, // a wins
      { par: 4, a: 3, b: 4 }, // a wins
      { par: 3, a: 2, b: 3 }, // a wins
      { par: 5, a: 4, b: 5 }, // a wins
      { par: 4, a: 4, b: 4 }, // halved
      { par: 4, a: 4, b: 4 }, // halved
    ])
    const s = computeMatchPlayStatus(r, 'a', 'b')
    expect(s.holesPlayed).toBe(6)
    expect(s.delta).toBe(4)
    expect(s.holesRemaining).toBe(3)
    expect(s.closed).toBe(true)
    expect(s.label).toBe('4&3')
  })

  it('uses N UP label when match is still open', () => {
    const r = makeMatch([
      { par: 4, a: 3, b: 4 },
      { par: 4, a: 4, b: 4 },
      { par: 3, a: 2, b: 3 },
    ])
    const s = computeMatchPlayStatus(r, 'a', 'b')
    expect(s.label).toBe('2 UP')
    expect(s.closed).toBe(false)
  })

  it('all square when wins balance out', () => {
    const r = makeMatch([
      { par: 4, a: 3, b: 4 }, // a wins
      { par: 4, a: 4, b: 3 }, // b wins
      { par: 3, a: 3, b: 3 }, // halved
    ])
    const s = computeMatchPlayStatus(r, 'a', 'b')
    expect(s.label).toBe('AS')
    expect(s.leaderUid).toBeNull()
  })

  it('skips holes where one player has no shots', () => {
    // hole 1: only Alice played; hole 2: both played, b wins
    const r = makeMatch([
      { par: 4, a: 3, b: 0 },
      { par: 4, a: 5, b: 4 },
    ])
    const s = computeMatchPlayStatus(r, 'a', 'b')
    expect(s.holesPlayed).toBe(1)
    expect(s.leaderUid).toBe('b')
  })
})

describe('computeLeaderboard', () => {
  function makeRoundWithPlayers(playerData: Array<{ uid: string; name: string; shots: number[] }>): Round {
    const allUids = playerData.map(p => p.uid)
    const players: Record<string, { name: string; avatar: string; totalScore: number; scoreDiff: number }> = {}
    for (const p of playerData) {
      players[p.uid] = { name: p.name, avatar: '', totalScore: 0, scoreDiff: 0 }
    }
    return {
      id: 'lb', courseId: 'c', courseName: 'T', totalHoles: 9, lobbyCode: 'X',
      status: 'active', hostId: allUids[0],
      players, playerIds: allUids,
      holes: [
        { holeNumber: 1, par: 4, distanceMeters: 360,
          shots: Object.fromEntries(playerData.filter(p => p.shots[0] > 0).map(p => [p.uid, { count: p.shots[0], clubs: [], updatedAt: new Date() }])) },
        { holeNumber: 2, par: 3, distanceMeters: 150,
          shots: Object.fromEntries(playerData.filter(p => p.shots[1] > 0).map(p => [p.uid, { count: p.shots[1], clubs: [], updatedAt: new Date() }])) },
        { holeNumber: 3, par: 5, distanceMeters: 480,
          shots: Object.fromEntries(playerData.filter(p => p.shots[2] > 0).map(p => [p.uid, { count: p.shots[2], clubs: [], updatedAt: new Date() }])) },
      ],
      startedAt: new Date(), finishedAt: null, createdAt: new Date(),
    }
  }

  it('sorts by scoreDiff ascending', () => {
    const round = makeRoundWithPlayers([
      { uid: 'a', name: 'Alice', shots: [5, 4, 6] }, // 15 vs par 12 = +3
      { uid: 'b', name: 'Bob',   shots: [4, 3, 5] }, // 12 vs par 12 = 0
      { uid: 'c', name: 'Carol', shots: [3, 3, 5] }, // 11 vs par 12 = -1
    ])
    const lb = computeLeaderboard(round)
    expect(lb.map(e => e.uid)).toEqual(['c', 'b', 'a'])
    expect(lb[0].scoreDiff).toBe(-1)
    expect(lb[2].scoreDiff).toBe(3)
  })

  it('reports thru correctly per player', () => {
    const round = makeRoundWithPlayers([
      { uid: 'a', name: 'Alice', shots: [4, 4, 0] }, // 2 of 3 holes
      { uid: 'b', name: 'Bob',   shots: [4, 4, 5] }, // all 3
    ])
    const lb = computeLeaderboard(round)
    const alice = lb.find(e => e.uid === 'a')
    const bob = lb.find(e => e.uid === 'b')
    expect(alice?.thru).toBe(2)
    expect(bob?.thru).toBe(3)
  })

  it('puts players with no shots at the bottom regardless of scoreDiff', () => {
    const round = makeRoundWithPlayers([
      { uid: 'a', name: 'Alice', shots: [0, 0, 0] }, // 0/3, scoreDiff = 0 (no data)
      { uid: 'b', name: 'Bob',   shots: [5, 4, 6] }, // +3
    ])
    const lb = computeLeaderboard(round)
    expect(lb[0].uid).toBe('b')
    expect(lb[1].uid).toBe('a')
  })
})
