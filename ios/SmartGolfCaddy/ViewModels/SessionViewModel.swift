// ios/SmartGolfCaddy/ViewModels/SessionViewModel.swift
import Foundation
import Observation

@Observable
@MainActor
final class SessionViewModel {
    enum State {
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
                return
            }
            self.state = .signedIn
            self.unsubscribeProfile = ProfileService.subscribeToProfile(
                uid: uid,
                onChange: { [weak self] user in self?.profile = user },
                onError: { [weak self] _ in
                    self?.errorMessage = "Не удалось загрузить профиль — проверьте сеть"
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

    func signOut() {
        do {
            try AuthService.signOut()
        } catch {
            errorMessage = "Не удалось выйти — попробуйте ещё раз"
        }
    }
}
