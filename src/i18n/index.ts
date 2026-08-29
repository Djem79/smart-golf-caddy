import { useSyncExternalStore } from 'react'
import { ru as ruDateFnsLocale, enUS as enDateFnsLocale } from 'date-fns/locale'
import type { Locale as DateFnsLocale } from 'date-fns'
import { ru } from './ru'
import { en } from './en'
import type { Dictionary } from './ru'
import type { Locale, PluralForms, PluralRuleName } from './types'

export type { Locale, PluralForms, PluralRuleName, Dictionary }

const dictionaries: Record<Locale, Dictionary> = { ru, en }

// --- Language detection -----------------------------------------------
//
// Default is "by device language": a Russian system locale (ru, ru-RU,
// ru-KZ, ...) gets the Russian UI, anything else gets English. Exported so
// T3's profile-load code (src/hooks/useLocaleSync.ts) can fall back to it
// when the profile has no saved `locale` (or the user signs out).
export function detectSystemLocale(): Locale {
  if (typeof navigator === 'undefined') return 'ru'
  const lang = navigator.language || navigator.languages?.[0] || ''
  return lang.toLowerCase().startsWith('ru') ? 'ru' : 'en'
}

let currentLocale: Locale = detectSystemLocale()
const listeners = new Set<() => void>()

export function getLocale(): Locale {
  return currentLocale
}

// T3: `useLocaleSync` (src/hooks/useLocaleSync.ts) calls this once the
// profile resolves — `setLocale(profile?.locale ?? detectSystemLocale())` —
// overriding the system default computed above. Every subscribed component
// (via `useT`) re-renders immediately — no page reload needed.
export function setLocale(locale: Locale): void {
  if (locale === currentLocale) return
  currentLocale = locale
  listeners.forEach(listener => listener())
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

/** Reactive hook — re-renders the calling component whenever `setLocale` changes the active language. */
export function useT(): { t: Dictionary; locale: Locale } {
  const locale = useSyncExternalStore(subscribe, getLocale, getLocale)
  return { t: dictionaries[locale], locale }
}

// --- Pluralization -------------------------------------------------------
//
// `Intl.PluralRules` is built into every evergreen browser and already knows
// CLDR's plural rules per locale (ru: one/few/many, en: one/other) — no need
// to ship or hand-maintain that logic. Dictionaries store the raw `forms`;
// this function picks the right one for `n`.
export function plural(n: number, locale: Locale, forms: PluralForms): string {
  const rule = new Intl.PluralRules(locale).select(n) as PluralRuleName
  return forms[rule] ?? forms.other ?? Object.values(forms)[0] ?? ''
}

// date-fns needs its own locale object (separate from ours) for formatting
// dates/months in the right language.
export function getDateFnsLocale(locale: Locale): DateFnsLocale {
  return locale === 'ru' ? ruDateFnsLocale : enDateFnsLocale
}
