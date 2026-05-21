import { describe, it, expect, vi, beforeEach } from 'vitest'

// Mock Firebase BEFORE importing rounds.ts so the imports resolve in test env.
vi.mock('../firebase', () => ({
  db: {},
  app: {},
}))

const mockArrayRemove = vi.fn((v) => ({ __op: 'arrayRemove', v }))

vi.mock('firebase/firestore', () => ({
  collection: vi.fn((_db, name) => ({ __collection: name })),
  doc: vi.fn((...args) => ({ __doc: args, id: 'mock-doc-id' })),
  setDoc: vi.fn(),
  updateDoc: vi.fn(),
  getDoc: vi.fn(),
  onSnapshot: vi.fn(),
  query: vi.fn((...parts) => ({ __query: parts })),
  where: vi.fn((f, op, v) => ({ __where: [f, op, v] })),
  orderBy: vi.fn((f, dir) => ({ __orderBy: [f, dir] })),
  getDocs: vi.fn(),
  serverTimestamp: vi.fn(() => ({ __serverTimestamp: true })),
  Timestamp: class Timestamp {
    constructor(public seconds: number, public nanoseconds = 0) {}
    toDate() { return new Date(this.seconds * 1000) }
    static fromDate(d: Date) { return new Timestamp(Math.floor(d.getTime() / 1000)) }
  },
  arrayRemove: (v: unknown) => mockArrayRemove(v),
}))

// `recordShot` and `joinRoundByCode` now delegate to Cloud Functions
// callables. We mock the dispatcher so tests can assert the right name +
// payload were dispatched, without spinning up an emulator.
type CallableCall = { name: string; payload: unknown }
const callableCalls: CallableCall[] = []
const callableResponses = new Map<string, unknown>()

vi.mock('firebase/functions', () => ({
  getFunctions: vi.fn(() => ({ __functions: true })),
  httpsCallable: (_fns: unknown, name: string) =>
    async (payload: unknown) => {
      callableCalls.push({ name, payload })
      const response = callableResponses.get(name)
      return { data: response ?? { ok: true } }
    },
}))

import {
  generateLobbyCode,
  buildDefaultHoles,
  joinRoundByCode,
  recordShot,
} from './rounds'

beforeEach(() => {
  vi.clearAllMocks()
  callableCalls.length = 0
  callableResponses.clear()
})

describe('generateLobbyCode', () => {
  it('generates a 6-character string', () => {
    expect(generateLobbyCode()).toHaveLength(6)
  })
  it('uses uppercase characters', () => {
    const code = generateLobbyCode()
    expect(code).toBe(code.toUpperCase())
  })
  it('generates different codes each time', () => {
    const codes = new Set(Array.from({ length: 20 }, () => generateLobbyCode()))
    expect(codes.size).toBeGreaterThan(15)
  })
})

describe('buildDefaultHoles', () => {
  it('builds 9 holes for 9-hole round', () => {
    expect(buildDefaultHoles(9)).toHaveLength(9)
  })
  it('builds 18 holes for 18-hole round', () => {
    expect(buildDefaultHoles(18)).toHaveLength(18)
  })
  it('each hole has holeNumber, par, distanceMeters, and empty shots', () => {
    const holes = buildDefaultHoles(9)
    for (const hole of holes) {
      expect(hole).toHaveProperty('holeNumber')
      expect(hole).toHaveProperty('par')
      expect(hole).toHaveProperty('distanceMeters')
      expect(hole.shots).toEqual({})
    }
  })
  it('hole numbers are 1-indexed', () => {
    const holes = buildDefaultHoles(9)
    expect(holes[0].holeNumber).toBe(1)
    expect(holes[8].holeNumber).toBe(9)
  })

  it('applies tee multiplier to distances', () => {
    const par4Default = 360
    const men    = buildDefaultHoles(18, 'men')
    const pro    = buildDefaultHoles(18, 'pro')
    const senior = buildDefaultHoles(18, 'senior')
    const ladies = buildDefaultHoles(18, 'ladies')

    // First par-4 hole exists in default; check multiplier ratios approximately
    const par4Idx = men.findIndex(h => h.par === 4)
    expect(par4Idx).toBeGreaterThanOrEqual(0)
    expect(men[par4Idx].distanceMeters).toBe(par4Default)
    expect(pro[par4Idx].distanceMeters).toBe(Math.round(par4Default * 1.10))
    expect(senior[par4Idx].distanceMeters).toBe(Math.round(par4Default * 0.90))
    expect(ladies[par4Idx].distanceMeters).toBe(Math.round(par4Default * 0.80))
  })

  it('defaults to men tees when no tee argument is given', () => {
    const noArg = buildDefaultHoles(9)
    const explicit = buildDefaultHoles(9, 'men')
    expect(noArg).toEqual(explicit)
  })
})

describe('joinRoundByCode', () => {
  const playerInfo = { name: 'Bob', avatar: '', totalScore: 0, scoreDiff: 0 }

  it('returns null for empty / whitespace-only code without calling the callable', async () => {
    expect(await joinRoundByCode('', 'uid', playerInfo)).toBeNull()
    expect(await joinRoundByCode('   ', 'uid', playerInfo)).toBeNull()
    expect(callableCalls).toHaveLength(0)
  })

  it('invokes joinLobbyByCode callable with uppercased+trimmed code', async () => {
    callableResponses.set('joinLobbyByCode', { roundId: 'round-123' })
    const result = await joinRoundByCode('  abcdef  ', 'guest-uid', playerInfo)
    expect(result).toBe('round-123')
    expect(callableCalls).toHaveLength(1)
    expect(callableCalls[0]).toEqual({
      name: 'joinLobbyByCode',
      payload: { code: 'ABCDEF', playerInfo },
    })
  })

  it('returns null when the callable says no lobby matched', async () => {
    callableResponses.set('joinLobbyByCode', { roundId: null })
    const result = await joinRoundByCode('ABCDEF', 'uid', playerInfo)
    expect(result).toBeNull()
  })
})

describe('recordShot', () => {
  it('dispatches a recordShot callable forwarding the target uid', async () => {
    await recordShot('rid-1', 4, 'player-2-uid', ['Driver', '7i', 'Putter'])
    expect(callableCalls).toHaveLength(1)
    expect(callableCalls[0]).toEqual({
      name: 'recordShot',
      payload: {
        roundId: 'rid-1',
        holeIndex: 4,
        clubs: ['Driver', '7i', 'Putter'],
        targetUid: 'player-2-uid',
      },
    })
  })

  // Server-side validation (auth uid mismatch, holeIndex out of range, etc.)
  // now lives in the Cloud Function and is covered by manual smoke tests
  // and Functions emulator runs. The client just passes payload through.
})
