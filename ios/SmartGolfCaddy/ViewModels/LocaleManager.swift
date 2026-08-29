// ios/SmartGolfCaddy/ViewModels/LocaleManager.swift
// T4 (iOS localization): the reactive, View-facing façade over
// AppLocaleStore (Models/Localization/AppLocaleStore.swift). Injected into
// the environment once at the root (see App/RootView.swift) — Views read
// `@Environment(LocaleManager.self)` and `lm.t.<screen>.<key>` so SwiftUI
// re-renders in place the instant the language changes, no relaunch.
// Mirrors src/i18n/index.ts's useT()/setLocale() pair.
import Observation

@Observable
@MainActor
final class LocaleManager {
    static let shared = LocaleManager()

    private(set) var current: AppLocale = AppLocaleStore.current

    private init() {}

    var t: Strings { current == .ru ? Strings.ru : Strings.en }

    /// Mirrors useLocaleSync on web: SessionViewModel calls this every time
    /// the profile resolves or changes. A saved `locale` overrides the
    /// system default; signed-out (or not-yet-loaded, profile == nil)
    /// falls back to it — so a previous user's saved language never leaks
    /// into the next sign-in.
    func sync(withProfile profile: AppUser?) {
        set(profile?.locale ?? AppLocaleStore.systemDefault)
    }

    /// Optimistic local switch — called directly from the profile screen's
    /// language picker. Applies immediately (every environment reader
    /// re-renders in place); UsersService.updateLocale persists to
    /// Firestore separately and non-critically (same pattern as
    /// MyBagViewModel.changeUnits).
    func set(_ locale: AppLocale) {
        guard locale != current else { return }
        current = locale
        AppLocaleStore.set(locale)
    }
}
