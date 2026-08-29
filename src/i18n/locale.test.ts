import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'

// The initial locale is computed once, at module load, from
// `navigator.language`. To test different system languages we have to stub
// `navigator.language` and re-import a fresh module instance each time
// (`vi.resetModules`), since a plain re-import would hit the cached module
// with its already-computed `currentLocale`.
describe('system locale detection', () => {
  const originalLanguage = navigator.language

  beforeEach(() => {
    vi.resetModules()
  })

  afterEach(() => {
    Object.defineProperty(navigator, 'language', { value: originalLanguage, configurable: true })
  })

  it('picks ru for a Russian system locale', async () => {
    Object.defineProperty(navigator, 'language', { value: 'ru-RU', configurable: true })
    const { getLocale } = await import('./index')
    expect(getLocale()).toBe('ru')
  })

  it('picks ru for other Russian-speaking regions (ru-KZ)', async () => {
    Object.defineProperty(navigator, 'language', { value: 'ru-KZ', configurable: true })
    const { getLocale } = await import('./index')
    expect(getLocale()).toBe('ru')
  })

  it('picks en for a non-Russian system locale', async () => {
    Object.defineProperty(navigator, 'language', { value: 'en-US', configurable: true })
    const { getLocale } = await import('./index')
    expect(getLocale()).toBe('en')
  })

  it('picks en for an unrelated locale (fr-FR)', async () => {
    Object.defineProperty(navigator, 'language', { value: 'fr-FR', configurable: true })
    const { getLocale } = await import('./index')
    expect(getLocale()).toBe('en')
  })
})

describe('setLocale', () => {
  beforeEach(() => {
    vi.resetModules()
  })

  it('overrides the detected locale and notifies subscribers', async () => {
    Object.defineProperty(navigator, 'language', { value: 'en-US', configurable: true })
    const { getLocale, setLocale } = await import('./index')
    expect(getLocale()).toBe('en')

    setLocale('ru')
    expect(getLocale()).toBe('ru')
  })
})
