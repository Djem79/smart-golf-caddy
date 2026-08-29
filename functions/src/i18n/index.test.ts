import { describe, expect, it } from 'vitest'
import { getDictionary, plural, resolveLocale } from './index'

describe('resolveLocale', () => {
  it('defaults to Russian when the profile has no locale field', () => {
    expect(resolveLocale(undefined)).toBe('ru')
  })

  it('defaults to Russian for a null value', () => {
    expect(resolveLocale(null)).toBe('ru')
  })

  it('defaults to Russian for an unexpected/corrupt value', () => {
    expect(resolveLocale('fr')).toBe('ru')
    expect(resolveLocale(42)).toBe('ru')
  })

  it('accepts an explicit "en"', () => {
    expect(resolveLocale('en')).toBe('en')
  })

  it('accepts an explicit "ru"', () => {
    expect(resolveLocale('ru')).toBe('ru')
  })
})

describe('plural', () => {
  const holesRu = getDictionary('ru').holesWord
  const holesEn = getDictionary('en').holesWord

  it('picks the Russian one/few/many forms correctly', () => {
    expect(plural(1, 'ru', holesRu)).toBe('лунка')
    expect(plural(2, 'ru', holesRu)).toBe('лунки')
    expect(plural(3, 'ru', holesRu)).toBe('лунки')
    expect(plural(5, 'ru', holesRu)).toBe('лунок')
    expect(plural(9, 'ru', holesRu)).toBe('лунок')
    expect(plural(18, 'ru', holesRu)).toBe('лунок')
    expect(plural(21, 'ru', holesRu)).toBe('лунка')
  })

  it('picks the English one/other forms correctly', () => {
    expect(plural(1, 'en', holesEn)).toBe('hole')
    expect(plural(2, 'en', holesEn)).toBe('holes')
    expect(plural(9, 'en', holesEn)).toBe('holes')
    expect(plural(18, 'en', holesEn)).toBe('holes')
  })
})

describe('getDictionary', () => {
  it('returns a distinct dictionary per locale with matching key shape', () => {
    const ru = getDictionary('ru')
    const en = getDictionary('en')
    expect(ru.title).toBe('Итоги раунда')
    expect(en.title).toBe('Round summary')
    expect(Object.keys(ru).sort()).toEqual(Object.keys(en).sort())
  })
})
