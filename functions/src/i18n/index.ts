import { ru } from './ru'
import { en } from './en'
import type { Dictionary } from './ru'
import type { Locale, PluralForms, PluralRuleName } from './types'

export type { Locale, PluralForms, PluralRuleName, Dictionary }

const dictionaries: Record<Locale, Dictionary> = { ru, en }

export function getDictionary(locale: Locale): Dictionary {
  return dictionaries[locale]
}

// Normalizes whatever is stored in users/{uid}.locale into a Locale, always
// falling back to Russian — matches the pre-localization behaviour (every
// existing user effectively saw Russian) so accounts that predate this
// field, or a corrupt/unexpected value, see no change in the language of
// their emails.
export function resolveLocale(raw: unknown): Locale {
  return raw === 'en' ? 'en' : 'ru'
}

// Same picker as the web app's src/i18n/index.ts `plural()` — Intl.PluralRules
// is built into Node and already knows CLDR's plural rules per locale (ru:
// one/few/many, en: one/other), so there's nothing to hand-maintain here.
export function plural(n: number, locale: Locale, forms: PluralForms): string {
  const rule = new Intl.PluralRules(locale).select(n) as PluralRuleName
  return forms[rule] ?? forms.other ?? Object.values(forms)[0] ?? ''
}
