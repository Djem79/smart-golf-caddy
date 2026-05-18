import { describe, it, expect } from 'vitest'
import { scoreColor, scoreLabel, DEFAULT_CLUBS, CLUB_ABBREV, DEFAULT_HOLE_PARS } from './index'

describe('scoreColor', () => {
  it('returns gold (#FFD700) for eagle (-2)', () => {
    expect(scoreColor(-2)).toBe('#FFD700')
  })
  it('returns gold for albatross (-3)', () => {
    expect(scoreColor(-3)).toBe('#FFD700')
  })
  it('returns green (#4CAF50) for birdie (-1)', () => {
    expect(scoreColor(-1)).toBe('#4CAF50')
  })
  it('returns white (#FFFFFF) for par (0)', () => {
    expect(scoreColor(0)).toBe('#FFFFFF')
  })
  it('returns orange (#FF9800) for bogey (+1)', () => {
    expect(scoreColor(1)).toBe('#FF9800')
  })
  it('returns red (#F44336) for double bogey (+2)', () => {
    expect(scoreColor(2)).toBe('#F44336')
  })
  it('returns red for triple bogey (+3)', () => {
    expect(scoreColor(3)).toBe('#F44336')
  })
})

describe('scoreLabel', () => {
  it('returns "Eagle" for -2', () => expect(scoreLabel(-2)).toBe('Eagle'))
  it('returns "Eagle" for -3 (albatross shown as Eagle)', () => expect(scoreLabel(-3)).toBe('Eagle'))
  it('returns "Birdie" for -1', () => expect(scoreLabel(-1)).toBe('Birdie'))
  it('returns "Par" for 0', () => expect(scoreLabel(0)).toBe('Par'))
  it('returns "Bogey" for +1', () => expect(scoreLabel(1)).toBe('Bogey'))
  it('returns "Double" for +2', () => expect(scoreLabel(2)).toBe('Double'))
  it('returns "+5" for 5', () => expect(scoreLabel(5)).toBe('+5'))
})

describe('DEFAULT_CLUBS', () => {
  it('contains Putter', () => expect(DEFAULT_CLUBS).toContain('Putter'))
  it('contains Driver', () => expect(DEFAULT_CLUBS).toContain('Driver'))
  it('has 14 clubs', () => expect(DEFAULT_CLUBS).toHaveLength(14))
})

describe('CLUB_ABBREV', () => {
  it('has an abbreviation for every DEFAULT_CLUB', () => {
    for (const club of DEFAULT_CLUBS) {
      expect(CLUB_ABBREV).toHaveProperty(club)
    }
  })
})

describe('DEFAULT_HOLE_PARS', () => {
  it('has 9 holes for 9-hole config', () => expect(DEFAULT_HOLE_PARS[9]).toHaveLength(9))
  it('has 18 holes for 18-hole config', () => expect(DEFAULT_HOLE_PARS[18]).toHaveLength(18))
  it('all pars are 3, 4, or 5', () => {
    for (const par of [...DEFAULT_HOLE_PARS[9], ...DEFAULT_HOLE_PARS[18]]) {
      expect([3, 4, 5]).toContain(par)
    }
  })
})
