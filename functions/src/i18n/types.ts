// Shared types for the Functions-side i18n layer. Deliberately NOT imported
// from the web app's `src/i18n` — this is a separate TypeScript project
// (its own package.json/tsconfig, no shared build step), so it keeps its
// own tiny dictionaries rather than reaching across the project boundary.
// The shapes mirror src/i18n/types.ts on purpose (same mechanism, same
// mental model) but are independent copies.

export type Locale = 'ru' | 'en'

// Mirrors Intl.PluralRules' `LDMLPluralRule` return values.
export type PluralRuleName = 'zero' | 'one' | 'two' | 'few' | 'many' | 'other'

// Not every locale uses every category (Russian: one/few/many; English:
// one/other) — Partial lets each language's dictionary declare only the
// forms it needs.
export type PluralForms = Partial<Record<PluralRuleName, string>>
