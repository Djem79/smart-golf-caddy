// ios/SmartGolfCaddy/ViewModels/SessionViewModel.swift
import Foundation
import Observation

@Observable
@MainActor
final class SessionViewModel {
    enum State: Equatable {
        case loading, signedOut, signedIn
    }

    var state: State = .loading
    var profile: AppUser?
    var errorMessage: String?
    var isSigningIn = false

    private var unsubscribeAuth: (() -> Void)?
    private var unsubscribeProfile: (() -> Void)?

    func start() {
        unsubscribeAuth = AuthService.subscribe { [weak self] uid in
            guard let self else { return }
            self.unsubscribeProfile?()
            self.unsubscribeProfile = nil
            self.profile = nil
            guard let uid else {
                self.state = .signedOut
                // T4: signed-out (or between sessions) falls back to the
                // system default — a previous user's saved language must
                // never leak into the next sign-in.
                LocaleManager.shared.sync(withProfile: nil)
                return
            }
            self.state = .signedIn
            self.unsubscribeProfile = ProfileService.subscribeToProfile(
                uid: uid,
                onChange: { [weak self] user in
                    self?.profile = user
                    // T4: mirrors useLocaleSync on web — a saved
                    // AppUser.locale overrides the system default the
                    // instant the profile resolves/changes.
                    LocaleManager.shared.sync(withProfile: user)
                },
                onError: { [weak self] _ in
                    self?.errorMessage = AppLocaleStore.strings.common.loadProfileError
                }
            )
        }
    }

    func signIn() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        errorMessage = nil
        do {
            try await AuthService.signInWithGoogle()
        } catch AuthServiceError.cancelled {
            // пользователь закрыл окно входа — не ошибка
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // Sign in with Apple: AuthService.signInWithApple(result:rawNonce:)
    // needs `Result<ASAuthorization, Error>` from SwiftUI's
    // SignInWithAppleButton.onCompletion — that type lives in
    // AuthenticationServices, which per ios/CLAUDE.md's import boundary
    // stays confined to Services/ and the button file, NOT ViewModels/.
    // So AppleSignInButton calls AuthService directly and reports back
    // through this plain `Error?` pair, mirroring the isSigningIn/
    // errorMessage bookkeeping signIn() does for Google.
    func beginSigningIn() {
        errorMessage = nil
        isSigningIn = true
    }

    func finishSigningIn(error: Error?) {
        isSigningIn = false
        guard let error else { return }
        if case AuthServiceError.cancelled = error { return }   // тихо, не ошибка
        errorMessage = error.localizedDescription
    }

    func signOut() {
        do {
            try AuthService.signOut()
        } catch {
            errorMessage = AppLocaleStore.strings.profile.signOutError
        }
    }

    @MainActor deinit {
        unsubscribeAuth?()
        unsubscribeProfile?()
    }
}
