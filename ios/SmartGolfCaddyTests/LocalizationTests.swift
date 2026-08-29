// ios/SmartGolfCaddyTests/LocalizationTests.swift
// T4 (iOS localization). Covers the two moving parts the plan calls out as
// easy to get wrong: pluralization (ru needs three CLDR forms, en two) and
// locale resolution precedence (profile overrides the system default;
// a missing/nil field falls back to it). Mirrors src/i18n/plural.test.ts +
// src/i18n/locale.test.ts on web.
import XCTest
@testable import SmartGolfCaddy

final class LocalizationTests: XCTestCase {

    // MARK: plural() — Russian (one/few/many)

    // Numbers picked because they're exactly where a naive "n == 1 ? one :
    // other" (or a mod-10-only rule) breaks: the 11-14 exception to the
    // mod-10 rule, and where that exception itself resets at 21/22/25.
    func testPluralRussianForms() {
        let forms = PluralForms(one: "лунка", few: "лунки", many: "лунок")
        let cases: [(Int, String)] = [
            (1, "лунка"), (2, "лунки"), (5, "лунок"),
            (11, "лунок"), (12, "лунок"),
            (21, "лунка"), (22, "лунки"), (25, "лунок"),
            (101, "лунка"), (111, "лунок"),
        ]
        for (n, expected) in cases {
            XCTAssertEqual(plural(n, .ru, forms), expected, "n=\(n)")
        }
    }

    func testPluralRussianNegativeMirrorsPositive() {
        let forms = PluralForms(one: "лунка", few: "лунки", many: "лунок")
        XCTAssertEqual(plural(-1, .ru, forms), "лунка")
        XCTAssertEqual(plural(-11, .ru, forms), "лунок")
    }

    // MARK: plural() — English (one/other, "few"/"many" collapse to the same word)

    func testPluralEnglishForms() {
        let forms = PluralForms(one: "hole", few: "holes", many: "holes")
        let cases: [(Int, String)] = [
            (1, "hole"),
            (2, "holes"), (5, "holes"),
            (11, "holes"), (12, "holes"),
            (21, "holes"), (22, "holes"), (25, "holes"),
            (101, "holes"), (111, "holes"),
        ]
        for (n, expected) in cases {
            XCTAssertEqual(plural(n, .en, forms), expected, "n=\(n)")
        }
    }

    // MARK: Strings.ru / Strings.en — shape and a couple of real dictionary entries

    func testDictionaryPluralWordsPickCorrectForm() {
        XCTAssertEqual(plural(1, .ru, Strings.ru.common.holesWord), "лунка")
        XCTAssertEqual(plural(11, .ru, Strings.ru.common.holesWord), "лунок")
        XCTAssertEqual(plural(1, .en, Strings.en.common.holesWord), "hole")
        XCTAssertEqual(plural(11, .en, Strings.en.common.holesWord), "holes")
    }

    // MARK: LocaleManager — resolution precedence (mirrors useLocaleSync on web)

    @MainActor
    func testProfileLocaleOverridesSystemDefault() {
        let lm = LocaleManager.shared
        let opposite: AppLocale = AppLocaleStore.systemDefault == .ru ? .en : .ru
        let user = AppUser(uid: "u1", data: ["name": "Д", "locale": opposite.rawValue])
        lm.sync(withProfile: user)
        XCTAssertEqual(lm.current, opposite)
    }

    @MainActor
    func testMissingLocaleFallsBackToSystemDefault() {
        let lm = LocaleManager.shared
        // Land on the non-default locale first so the fallback below is a
        // real assertion, not a no-op that happened to already match.
        let opposite: AppLocale = AppLocaleStore.systemDefault == .ru ? .en : .ru
        lm.set(opposite)
        XCTAssertEqual(lm.current, opposite)

        // Profile with no `locale` field (e.g. a pre-T4 account) → system default.
        let user = AppUser(uid: "u1", data: ["name": "Д"])
        XCTAssertNil(user?.locale)
        lm.sync(withProfile: user)
        XCTAssertEqual(lm.current, AppLocaleStore.systemDefault)
    }

    @MainActor
    func testSignedOutFallsBackToSystemDefault() {
        let lm = LocaleManager.shared
        let opposite: AppLocale = AppLocaleStore.systemDefault == .ru ? .en : .ru
        lm.set(opposite)

        // Mirrors SessionViewModel.start()'s signed-out branch: nil profile
        // — a previous user's saved language must not leak into the next
        // sign-in.
        lm.sync(withProfile: nil)
        XCTAssertEqual(lm.current, AppLocaleStore.systemDefault)
    }

    @MainActor
    func testSetWritesThroughToAppLocaleStore() {
        let lm = LocaleManager.shared
        let opposite: AppLocale = AppLocaleStore.current == .ru ? .en : .ru
        lm.set(opposite)
        XCTAssertEqual(AppLocaleStore.current, opposite)
        XCTAssertEqual(lm.t.common.you, AppLocaleStore.strings.common.you)
    }
}
