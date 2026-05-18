import { describe, it, expect, vi } from 'vitest'

// Mock Firebase BEFORE importing rounds.ts so the imports resolve in test env
vi.mock('../firebase', () => ({
  db: {},
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

import { generateLobbyCode, buildDefaultHoles } from './rounds'

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
