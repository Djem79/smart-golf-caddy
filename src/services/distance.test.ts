import { describe, it, expect } from 'vitest'
import { haversineMetres } from './distance'

describe('haversineMetres', () => {
  it('returns 0 for identical coordinates', () => {
    expect(haversineMetres(55.751, 37.618, 55.751, 37.618)).toBe(0)
  })

  it('computes distance between Moscow and St Petersburg (630-680 km)', () => {
    const dist = haversineMetres(55.7558, 37.6176, 59.9311, 30.3609)
    expect(dist).toBeGreaterThan(630_000)
    expect(dist).toBeLessThan(680_000)
  })

  it('computes ~111 km for 1 degree of latitude', () => {
    const dist = haversineMetres(0, 0, 1, 0)
    expect(dist).toBeGreaterThan(110_000)
    expect(dist).toBeLessThan(112_000)
  })

  it('returns a positive number for two different points', () => {
    expect(haversineMetres(51.5, -0.1, 48.8, 2.3)).toBeGreaterThan(0)
  })
})
