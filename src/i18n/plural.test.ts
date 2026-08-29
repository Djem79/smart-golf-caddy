import { describe, it, expect } from 'vitest'
import { plural } from './index'

// `one` covers 1, 21, 31, ... (genitive sing.: "лунка")
// `few` covers 2-4, 22-24, ... (genitive plural sing.: "лунки")
// `many` covers 0, 5-20, 25-30, ... (genitive plural: "лунок")
// Values mirror the old pluralRu() helper (removed in T2 once its 29 call
// sites migrated to this Intl.PluralRules-backed mechanism) so the same
// edge cases — teens as an exception to the few/many split — stay covered.
describe('plural (ru)', () => {
  const forms = { one: 'лунка', few: 'лунки', many: 'лунок' }
  const cases: Array<[number, string]> = [
    [1, 'лунка'], [2, 'лунки'], [5, 'лунок'],
    [11, 'лунок'], [21, 'лунка'], [22, 'лунки'],
    [25, 'лунок'], [101, 'лунка'], [111, 'лунок'],
  ]

  for (const [n, expected] of cases) {
    it(`n=${n} → "${expected}"`, () => {
      expect(plural(n, 'ru', forms)).toBe(expected)
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
