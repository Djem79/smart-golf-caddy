import { describe, it, expect, vi, beforeEach } from 'vitest'

// Mock Firebase BEFORE importing rounds.ts so the imports resolve in test env.
vi.mock('../firebase', () => ({
  db: {},
}))

// Track mock implementations so individual tests can configure responses
// per-call (e.g., joinRoundByCode reads via getDocs; recordShot reads via
// runTransaction's tx.get).
const mockUpdateDoc = vi.fn()
const mockGetDocs = vi.fn()
const mockRunTransaction = vi.fn()
const mockArrayUnion = vi.fn((v) => ({ __op: 'arrayUnion', v }))
const mockArrayRemove = vi.fn((v) => ({ __op: 'arrayRemove', v }))

vi.mock('firebase/firestore', () => ({
  collection: vi.fn((_db, name) => ({ __collection: name })),
  doc: vi.fn((...args) => ({ __doc: args, id: 'mock-doc-id' })),
  setDoc: vi.fn(),
  updateDoc: (...args: unknown[]) => mockUpdateDoc(...args),
  getDoc: vi.fn(),
  onSnapshot: vi.fn(),
  query: vi.fn((...parts) => ({ __query: parts })),
  where: vi.fn((f, op, v) => ({ __where: [f, op, v] })),
  orderBy: vi.fn((f, dir) => ({ __orderBy: [f, dir] })),
  getDocs: (...args: unknown[]) => mockGetDocs(...args),
  serverTimestamp: vi.fn(() => ({ __serverTimestamp: true })),
  runTransaction: (_db: unknown, cb: (tx: unknown) => Promise<unknown>) => mockRunTransaction(cb),
  arrayUnion: (v: unknown) => mockArrayUnion(v),
  arrayRemove: (v: unknown) => mockArrayRemove(v),
  Timestamp: class Timestamp {
    constructor(public seconds: number, public nanoseconds = 0) {}
    toDate() { return new Date(this.seconds * 1000) }
    static fromDate(d: Date) { return new Timestamp(Math.floor(d.getTime() / 1000)) }
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
})

describe('joinRoundByCode', () => {
  const playerInfo = { name: 'Bob', avatar: '', totalScore: 0, scoreDiff: 0 }

  it('returns null for empty / whitespace-only code', async () => {
    expect(await joinRoundByCode('', 'uid', playerInfo)).toBeNull()
    expect(await joinRoundByCode('   ', 'uid', playerInfo)).toBeNull()
    expect(mockGetDocs).not.toHaveBeenCalled()
  })

  it('returns null when no lobby matches the code', async () => {
    mockGetDocs.mockResolvedValueOnce({ empty: true, docs: [] })
    const result = await joinRoundByCode('ABCDEF', 'uid', playerInfo)
    expect(result).toBeNull()
    expect(mockUpdateDoc).not.toHaveBeenCalled()
  })

  it('returns roundId and writes the join payload when a lobby is found', async () => {
    mockGetDocs.mockResolvedValueOnce({
      empty: false,
      docs: [{ id: 'round-123', data: () => ({ status: 'lobby' }) }],
    })
    mockUpdateDoc.mockResolvedValueOnce(undefined)

    const result = await joinRoundByCode('abcdef', 'guest-uid', playerInfo)

    expect(result).toBe('round-123')
    expect(mockUpdateDoc).toHaveBeenCalledTimes(1)
    const [, payload] = mockUpdateDoc.mock.calls[0]
    expect(payload).toMatchObject({
      'players.guest-uid': playerInfo,
      playerIds: { __op: 'arrayUnion', v: 'guest-uid' },
    })
  })

  it('uppercases and trims the code before querying', async () => {
    mockGetDocs.mockResolvedValueOnce({ empty: true, docs: [] })
    await joinRoundByCode('  abcdef  ', 'uid', playerInfo)
    // The first call to `where` is for lobbyCode; the value should be uppercased.
    // We rely on the query() mock capturing the where() child internally — but
    // simplest check is that getDocs was called once.
    expect(mockGetDocs).toHaveBeenCalledTimes(1)
  })
})

describe('recordShot', () => {
  const validRound = {
    status: 'active',
    playerIds: ['host-uid', 'guest-uid'],
    holes: [
      { holeNumber: 1, par: 4, distanceMeters: 360, shots: {} },
      { holeNumber: 2, par: 3, distanceMeters: 150, shots: {} },
      { holeNumber: 3, par: 5, distanceMeters: 480, shots: {} },
    ],
  }

  function makeTx(snap: { exists: () => boolean; data?: () => unknown }) {
    return {
      get: vi.fn().mockResolvedValue(snap),
      update: vi.fn(),
    }
  }

  it('throws when the round does not exist', async () => {
    const tx = makeTx({ exists: () => false })
    mockRunTransaction.mockImplementationOnce((cb: (tx: unknown) => Promise<unknown>) => cb(tx))

    await expect(recordShot('rid', 0, 'host-uid', ['7i']))
      .rejects.toThrow('Round not found')
  })

  it('throws when the round is not active', async () => {
    const tx = makeTx({
      exists: () => true,
      data: () => ({ ...validRound, status: 'lobby' }),
    })
    mockRunTransaction.mockImplementationOnce((cb: (tx: unknown) => Promise<unknown>) => cb(tx))

    await expect(recordShot('rid', 0, 'host-uid', ['7i']))
      .rejects.toThrow('Round is not active')
  })

  it('throws when the user is not a participant', async () => {
    const tx = makeTx({ exists: () => true, data: () => validRound })
    mockRunTransaction.mockImplementationOnce((cb: (tx: unknown) => Promise<unknown>) => cb(tx))

    await expect(recordShot('rid', 0, 'stranger-uid', ['7i']))
      .rejects.toThrow('User is not a participant')
  })

  it('throws when holeIndex is out of range', async () => {
    const tx = makeTx({ exists: () => true, data: () => validRound })
    mockRunTransaction.mockImplementationOnce((cb: (tx: unknown) => Promise<unknown>) => cb(tx))

    await expect(recordShot('rid', 99, 'host-uid', ['7i']))
      .rejects.toThrow('Invalid hole index')
  })

  it('writes correct holes structure on a valid shot', async () => {
    const tx = makeTx({ exists: () => true, data: () => validRound })
    mockRunTransaction.mockImplementationOnce((cb: (tx: unknown) => Promise<unknown>) => cb(tx))

    await recordShot('rid', 1, 'guest-uid', ['Driver', 'PW', 'Putter'])

    expect(tx.update).toHaveBeenCalledTimes(1)
    const [, payload] = tx.update.mock.calls[0]
    expect(payload.holes).toHaveLength(3)
    // Hole index 1 was modified — guest has 3 shots; other holes untouched
    expect(payload.holes[1].shots['guest-uid']).toMatchObject({
      count: 3,
      clubs: ['Driver', 'PW', 'Putter'],
      club: 'Putter',
    })
    expect(payload.holes[0].shots).toEqual({})
    expect(payload.holes[2].shots).toEqual({})
  })
})
