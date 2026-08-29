// ios/SmartGolfCaddy/Models/Localization/AppLocaleStore.swift
// T4 (iOS localization): thread-safe, process-wide "what language are we
// showing right now". Models/Services aren't MainActor-isolated (Clubs,
// TeeColor, CoursesService, GeolocationService, RoundsService — some run
// off-main, e.g. CoursesService's async request path), so they can't touch
// the MainActor `LocaleManager` (ViewModels/LocaleManager.swift) directly.
// This is the single writer-through target: `LocaleManager.set(_:)` is the
// only call site that mutates it, keeping the reactive (View-facing) and
// plain-global (everything else) pictures always in sync.
import Foundation

enum AppLocaleStore {
    private static let lock = NSLock()
    private static var _current: AppLocale = systemDefault

    /// Русская системная локаль (ru, ru-RU, ru-KZ, ...) → русский UI,
    /// любая другая → английский. Mirrors detectSystemLocale() in
    /// src/i18n/index.ts.
    static var systemDefault: AppLocale {
        let lang = Locale.preferredLanguages.first ?? Locale.current.identifier
        return lang.lowercased().hasPrefix("ru") ? .ru : .en
    }

    static var current: AppLocale {
        lock.lock(); defer { lock.unlock() }
        return _current
    }

    static func set(_ locale: AppLocale) {
        lock.lock()
        _current = locale
        lock.unlock()
    }

    static var strings: Strings { current == .ru ? Strings.ru : Strings.en }
}
