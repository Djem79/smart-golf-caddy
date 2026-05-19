import { describe, it, expect } from 'vitest'
import {
  scoreColor, scoreDirection, scoreLabel, DEFAULT_CLUBS, CLUB_ABBREV, DEFAULT_HOLE_PARS,
  DEFAULT_BAG, getBagFromUser, enabledBagClubs, getClubCategory, getClubLabel,
  metersToYards, yardsToMeters,
} from './index'

describe('scoreColor', () => {
  // Colors tuned for WCAG AA contrast against #1A1C1C text — see types/index.ts
  it('returns gold (#FFD700) for eagle (-2)', () => {
    expect(scoreColor(-2)).toBe('#FFD700')
  })
  it('returns gold for albatross (-3)', () => {
    expect(scoreColor(-3)).toBe('#FFD700')
  })
  it('returns dark green (#2E7D32) for birdie (-1)', () => {
    expect(scoreColor(-1)).toBe('#2E7D32')
  })
  it('returns white (#FFFFFF) for par (0)', () => {
    expect(scoreColor(0)).toBe('#FFFFFF')
  })
  it('returns deep orange (#EF6C00) for bogey (+1)', () => {
    expect(scoreColor(1)).toBe('#EF6C00')
  })
  it('returns deep red (#C62828) for double bogey (+2)', () => {
    expect(scoreColor(2)).toBe('#C62828')
  })
  it('returns deep red for triple bogey (+3)', () => {
    expect(scoreColor(3)).toBe('#C62828')
  })
})

describe('scoreDirection', () => {
  it('returns "under" for any negative delta', () => {
    expect(scoreDirection(-1)).toBe('under')
    expect(scoreDirection(-2)).toBe('under')
    expect(scoreDirection(-5)).toBe('under')
  })
  it('returns "par" for zero', () => {
    expect(scoreDirection(0)).toBe('par')
  })
  it('returns "over" for any positive delta', () => {
    expect(scoreDirection(1)).toBe('over')
    expect(scoreDirection(3)).toBe('over')
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
  // DEFAULT_CLUBS / DEFAULT_BAG now act as a palette — users pick 14 to enable.
  it('has at least 14 options (the USGA-legal cap)', () =>
    expect(DEFAULT_CLUBS.length).toBeGreaterThanOrEqual(14))
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

describe('DEFAULT_BAG', () => {
  it('matches DEFAULT_CLUBS one-to-one', () => {
    expect(DEFAULT_BAG).toHaveLength(DEFAULT_CLUBS.length)
    for (const club of DEFAULT_BAG) {
      expect(DEFAULT_CLUBS).toContain(club.id)
    }
  })
  it('Putter has distance 0', () => {
    expect(DEFAULT_BAG.find(c => c.id === 'Putter')?.distanceMeters).toBe(0)
  })
  it('Driver has the longest distance', () => {
    const driver = DEFAULT_BAG.find(c => c.id === 'Driver')!
    for (const club of DEFAULT_BAG) {
      if (club.id === 'Driver') continue
      expect(club.distanceMeters).toBeLessThanOrEqual(driver.distanceMeters)
    }
  })
})

describe('getBagFromUser', () => {
  it('returns DEFAULT_BAG for null user', () => {
    expect(getBagFromUser(null)).toBe(DEFAULT_BAG)
  })
  it('returns user.bag if present (with category backfilled)', () => {
    const userBag = [{ id: 'Driver', distanceMeters: 250, enabled: true }]
    const result = getBagFromUser({ bag: userBag })
    expect(result).toHaveLength(1)
    expect(result[0].id).toBe('Driver')
    expect(result[0].distanceMeters).toBe(250)
    expect(result[0].category).toBe('wood')
  })
  it('migrates legacy clubs[] to bag with matching enabled flags', () => {
    const bag = getBagFromUser({ clubs: ['Driver', '7i', 'Putter'] })
    expect(bag.find(c => c.id === 'Driver')?.enabled).toBe(true)
    expect(bag.find(c => c.id === '7i')?.enabled).toBe(true)
    expect(bag.find(c => c.id === 'Putter')?.enabled).toBe(true)
    expect(bag.find(c => c.id === '3W')?.enabled).toBe(false)
    expect(bag).toHaveLength(DEFAULT_BAG.length)
  })
})

describe('enabledBagClubs', () => {
  it('filters out disabled clubs', () => {
    const result = enabledBagClubs(DEFAULT_BAG)
    expect(result.length).toBeLessThan(DEFAULT_BAG.length)
    expect(result.every(c => c.enabled)).toBe(true)
  })
})

describe('getClubCategory', () => {
  it('uses explicit category when present', () => {
    expect(getClubCategory({ id: 'custom-1', distanceMeters: 0, enabled: true, category: 'wedge' })).toBe('wedge')
  })
  it('infers wood from Driver', () => {
    expect(getClubCategory({ id: 'Driver', distanceMeters: 0, enabled: true })).toBe('wood')
  })
  it('infers iron from 7i', () => {
    expect(getClubCategory({ id: '7i', distanceMeters: 0, enabled: true })).toBe('iron')
  })
  it('infers wedge from PW', () => {
    expect(getClubCategory({ id: 'PW', distanceMeters: 0, enabled: true })).toBe('wedge')
  })
  it('infers putter from Putter', () => {
    expect(getClubCategory({ id: 'Putter', distanceMeters: 0, enabled: true })).toBe('putter')
  })
  it('defaults to iron for unknown id with no explicit category', () => {
    expect(getClubCategory({ id: 'mystery', distanceMeters: 0, enabled: true })).toBe('iron')
  })
})

describe('getBagFromUser backfills category', () => {
  it('adds category to legacy clubs in stored bag', () => {
    const bag = getBagFromUser({ bag: [
      { id: 'Driver', distanceMeters: 230, enabled: true },
      { id: '7i', distanceMeters: 140, enabled: true },
    ] })
    expect(bag[0].category).toBe('wood')
    expect(bag[1].category).toBe('iron')
  })
  it('preserves custom clubs with explicit category', () => {
    const custom = { id: 'custom-abc', distanceMeters: 180, enabled: true, category: 'wood' as const, custom: true }
    const bag = getBagFromUser({ bag: [custom] })
    expect(bag).toEqual([custom])
  })
})

describe('distance unit conversion', () => {
  it('converts metres to yards', () => {
    expect(metersToYards(100)).toBe(109)
    expect(metersToYards(150)).toBe(164)
  })
  it('converts yards to metres', () => {
    expect(yardsToMeters(100)).toBe(91)
    expect(yardsToMeters(150)).toBe(137)
  })
  it('roundtrip is approximately stable', () => {
    const start = 200
    const roundtrip = yardsToMeters(metersToYards(start))
    expect(Math.abs(roundtrip - start)).toBeLessThan(2)
  })
})

describe('getClubLabel', () => {
  const customBag = [
    ...DEFAULT_BAG,
    { id: 'custom-abc', customName: 'Hybrid 3', distanceMeters: 180, enabled: true, category: 'wood' as const, custom: true },
    { id: 'custom-noname', customName: undefined, distanceMeters: 0, enabled: true, category: 'iron' as const, custom: true },
  ]

  it('returns abbreviation for default clubs', () => {
    expect(getClubLabel('Driver', DEFAULT_BAG)).toBe('DRV')
    expect(getClubLabel('7i', DEFAULT_BAG)).toBe('7i')
    expect(getClubLabel('Putter', DEFAULT_BAG)).toBe('PT')
  })

  it('returns customName for custom clubs present in the bag', () => {
    expect(getClubLabel('custom-abc', customBag)).toBe('Hybrid 3')
  })

  it('returns "Клюшка" for custom ids missing from the bag', () => {
    expect(getClubLabel('custom-deleted', [])).toBe('Клюшка')
  })

  it('returns "Клюшка" for custom clubs in the bag but without a customName', () => {
    expect(getClubLabel('custom-noname', customBag)).toBe('Клюшка')
  })

  it('returns the id unchanged for unknown non-custom ids', () => {
    expect(getClubLabel('Wedge99', [])).toBe('Wedge99')
  })
})
