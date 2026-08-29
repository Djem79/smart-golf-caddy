// ios/SmartGolfCaddy/Models/Localization/PluralForms.swift
// T4 (iOS localization): mirrors src/i18n/index.ts's `plural(n, locale,
// forms)` + `PluralForms`. Swift has no `Intl.PluralRules`, so the CLDR
// rule for Russian is hand-rolled here (ported from the pre-T4 `pluralRu`
// helper, which this replaces — one pluralization mechanism, not two).
// Russian needs three forms (one/few/many); English only ever needs two,
// so `few` and `many` are simply equal at the call site for `en` — see
// Strings.swift.
import Foundation

struct PluralForms {
    let one: String
    let few: String
    let many: String
}

/// Picks the right form of `forms` for `n` in `locale`. Verified against
/// the numbers that are easy to get wrong: 1, 2, 5, 11, 12, 21, 22, 25,
/// 101, 111 (see LocalizationTests.swift).
func plural(_ n: Int, _ locale: AppLocale, _ forms: PluralForms) -> String {
    switch locale {
    case .en:
        return abs(n) == 1 ? forms.one : forms.many
    case .ru:
        let absN = abs(n)
        let mod10 = absN % 10
        let mod100 = absN % 100
        if mod10 == 1 && mod100 != 11 { return forms.one }
        if mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) { return forms.few }
        return forms.many
    }
}
