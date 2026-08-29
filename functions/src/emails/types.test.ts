import { describe, expect, it } from 'vitest'
import { getDictionary } from '../i18n'
import { categorize, categoryLabel, formatDiff } from './types'

describe('categoryLabel', () => {
  it('keeps golf jargon (Eagle/Birdie/Par/Bogey/Double) verbatim in both locales', () => {
    const ru = getDictionary('ru')
    const en = getDictionary('en')
    for (const cat of ['eagle', 'birdie', 'par', 'bogey', 'double'] as const) {
      expect(categoryLabel(cat, ru)).toBe(categoryLabel(cat, en))
    }
  })

  it('localizes the "worse" bucket (diff >= 3) per recipient locale', () => {
    expect(categoryLabel('worse', getDictionary('ru'))).toBe('Хуже')
    expect(categoryLabel('worse', getDictionary('en'))).toBe('Worse')
  })

  it('renders "empty" the same in both locales', () => {
    expect(categoryLabel('empty', getDictionary('ru'))).toBe('—')
    expect(categoryLabel('empty', getDictionary('en'))).toBe('—')
  })
})

describe('categorize', () => {
  it('buckets a diff of 3 or more as "worse", independent of locale', () => {
    expect(categorize(3)).toBe('worse')
    expect(categorize(10)).toBe('worse')
  })
})

describe('formatDiff', () => {
  it('uses the universal "E" notation for an even score in both locales (never translated)', () => {
    expect(formatDiff(0)).toBe('E')
  })
})
