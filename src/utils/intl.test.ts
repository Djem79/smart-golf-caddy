import { describe, it, expect } from 'vitest'
import { pluralRu } from './intl'

describe('pluralRu', () => {
  const w = (n: number) => pluralRu(n, 'лунка', 'лунки', 'лунок')

  it('uses "one" for 1', () => expect(w(1)).toBe('лунка'))
  it('uses "few" for 2', () => expect(w(2)).toBe('лунки'))
  it('uses "few" for 3', () => expect(w(3)).toBe('лунки'))
  it('uses "few" for 4', () => expect(w(4)).toBe('лунки'))
  it('uses "many" for 0', () => expect(w(0)).toBe('лунок'))
  it('uses "many" for 5', () => expect(w(5)).toBe('лунок'))
  it('uses "many" for 11 (teen exception)', () => expect(w(11)).toBe('лунок'))
  it('uses "many" for 12 (teen exception)', () => expect(w(12)).toBe('лунок'))
  it('uses "many" for 13 (teen exception)', () => expect(w(13)).toBe('лунок'))
  it('uses "many" for 14 (teen exception)', () => expect(w(14)).toBe('лунок'))
  it('uses "one" for 21', () => expect(w(21)).toBe('лунка'))
  it('uses "few" for 22', () => expect(w(22)).toBe('лунки'))
  it('uses "many" for 25', () => expect(w(25)).toBe('лунок'))
  it('uses "one" for 101', () => expect(w(101)).toBe('лунка'))
  it('uses "many" for 111', () => expect(w(111)).toBe('лунок'))
})
