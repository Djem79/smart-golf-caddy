import { describe, it, expect, vi } from 'vitest'

// Mock Firebase BEFORE importing RoundResults so the imports resolve in test env
vi.mock('../firebase', () => ({
  db: {},
  auth: {},
}))
vi.mock('firebase/firestore', () => ({
  collection: vi.fn(),
  doc: vi.fn(),
  setDoc: vi.fn(),
  updateDoc: vi.fn(),
  getDoc: vi.fn(),
  onSnapshot: vi.fn(),
  query: vi.fn(),
  where: vi.fn(),
  orderBy: vi.fn(),
  getDocs: vi.fn(),
  serverTimestamp: vi.fn(),
}))

import { computePlayerTotals } from './RoundResults'
import type { Round, HoleConfig } from '../types'

function makeRound(overrides: Partial<Round> = {}): Round {
  const holes: HoleConfig[] = [
    { holeNumber: 1, par: 4, distanceMeters: 360, shots: { uid1: { count: 3, clubs: ['Driver', '7i', 'Putter'], updatedAt: new Date() } } },
    { holeNumber: 2, par: 3, distanceMeters: 150, shots: { uid1: { count: 4, clubs: ['7i', 'PW', 'PW', 'Putter'], updatedAt: new Date() } } },
    { holeNumber: 3, par: 5, distanceMeters: 480, shots: { uid1: { count: 5, clubs: ['Driver', '3W', '7i', 'PW', 'Putter'], updatedAt: new Date() } } },
  ]
  return {
    id: 'r1', courseId: 'c1', courseName: 'Test Course',
    totalHoles: 9, lobbyCode: 'ABC123', status: 'finished', hostId: 'uid1',
    players: { uid1: { name: 'Alice', avatar: '', totalScore: 0, scoreDiff: 0 } },
    playerIds: ['uid1'],
    holes, startedAt: new Date(), finishedAt: new Date(), createdAt: new Date(),
    ...overrides,
  }
}

describe('computePlayerTotals', () => {
  it('computes total score and scoreDiff for a player', () => {
    const round = makeRound()
    const result = computePlayerTotals(round, 'uid1')
    // shots: 3+4+5=12, par: 4+3+5=12, diff=0
    expect(result.totalScore).toBe(12)
    expect(result.scoreDiff).toBe(0)
  })

  it('returns 0/0 for a player with no shots recorded', () => {
    const round = makeRound()
    const result = computePlayerTotals(round, 'unknown-uid')
    expect(result.totalScore).toBe(0)
    expect(result.scoreDiff).toBe(0)
  })

  it('correctly computes negative scoreDiff (under par)', () => {
    const round = makeRound()
    round.holes[0].shots['uid1'] = { count: 2, clubs: ['Driver', '7i'], updatedAt: new Date() }
    round.holes[1].shots['uid1'] = { count: 3, clubs: ['7i', 'PW', 'Putter'], updatedAt: new Date() }
    // shots: 2+3+5=10, par: 4+3+5=12, diff=-2
    const result = computePlayerTotals(round, 'uid1')
    expect(result.totalScore).toBe(10)
    expect(result.scoreDiff).toBe(-2)
  })
})
