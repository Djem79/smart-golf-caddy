// Shared types for the i18n layer. Kept separate from ru.ts/en.ts/index.ts so
// dictionaries can import the `PluralForms` shape without a runtime import
// cycle back through index.ts (type-only imports are erased at build time
// either way, but this keeps the dependency graph easy to reason about).

export type Locale = 'ru' | 'en'

// Mirrors Intl.PluralRules' `LDMLPluralRule` return values.
export type PluralRuleName = 'zero' | 'one' | 'two' | 'few' | 'many' | 'other'

// Not every locale uses every category (Russian: one/few/many; English:
// one/other) — Partial lets each language's dictionary declare only the
// forms it needs.
export type PluralForms = Partial<Record<PluralRuleName, string>>
