import { describe, it, expect } from 'vitest'
import { plural } from './index'
import { pluralRu } from '../utils/intl'

// Proves the new `Intl.PluralRules`-backed mechanism produces the exact same
// Russian forms as the existing `pluralRu` helper, for the numbers called
// out in the localization plan. `pluralRu` stays in place until its 29
// call sites migrate in T2 — the two must agree in the meantime.
describe('plural (ru) matches pluralRu', () => {
  const forms = { one: 'лунка', few: 'лунки', many: 'лунок' }
  const numbers = [1, 2, 5, 11, 21, 22, 25, 101, 111]

  for (const n of numbers) {
    it(`n=${n}`, () => {
      const legacy = pluralRu(n, 'лунка', 'лунки', 'лунок')
      const next = plural(n, 'ru', forms)
      expect(next).toBe(legacy)
    })
  }
})

describe('plural (en)', () => {
  const forms = { one: 'hole', other: 'holes' }

  it('uses "one" for 1', () => expect(plural(1, 'en', forms)).toBe('hole'))
  it('uses "other" for 0', () => expect(plural(0, 'en', forms)).toBe('holes'))
  it('uses "other" for 2', () => expect(plural(2, 'en', forms)).toBe('holes'))
  it('uses "other" for 11', () => expect(plural(11, 'en', forms)).toBe('holes'))
  it('uses "other" for 21', () => expect(plural(21, 'en', forms)).toBe('holes'))
})

describe('plural fallback', () => {
  it('falls back to the first available form when the exact category is missing', () => {
    expect(plural(2, 'en', { one: 'hole' })).toBe('hole')
  })
})
