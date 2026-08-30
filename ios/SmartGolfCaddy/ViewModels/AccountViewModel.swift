// ios/SmartGolfCaddy/ViewModels/AccountViewModel.swift
// Task 3, фаза 3d-1: удаление аккаунта из профиля (App Store 5.1.1(v)).
// `deleter` инжектируется — тесты подменяют сеть (образец JoinGameViewModel).
// Эта VM НЕ делает signOut/навигацию сама — confirmDelete() возвращает
// успех/провал, ProfileView вызывает session.signOut() ТОЛЬКО при true.
// Так неудачное удаление (данные могли не удалиться) никогда не
// разлогинивает пользователя — паритет с web/services/account.ts.
//
// Sign in with Apple (TN3194): если аккаунт привязан к Apple, ПЕРЕД
// удалением отзывается токен Apple (`revoker`; свежая авторизация Apple +
// Firebase revokeToken). Провал отзыва оставляет аккаунт нетронутым с
// понятным сообщением; отмена пользователем — тихо. Зеркало
// handleDeleteAccount в src/screens/Profile.tsx.
import Foundation
import Observation

@Observable
@MainActor
final class AccountViewModel {
    var showDeleteConfirm = false
    var deletingAccount = false
    var deleteError: String?

    private let needsAppleRevocation: () -> Bool
    private let revoker: () async throws -> Void
    private let deleter: () async throws -> Void

    convenience init() {
        self.init(
            needsAppleRevocation: { AuthService.isAppleLinked },
            revoker: { try await AuthService.revokeAppleToken() },
            deleter: { try await AccountService.deleteAccount() }
        )
    }

    init(
        needsAppleRevocation: @escaping () -> Bool = { false },
        revoker: @escaping () async throws -> Void = {},
        deleter: @escaping () async throws -> Void
    ) {
        self.needsAppleRevocation = needsAppleRevocation
        self.revoker = revoker
        self.deleter = deleter
    }

    /// true — удаление на сервере прошло успешно, вызывающий обязан выйти
    /// из аккаунта. false — ничего не трогать, кнопка снова доступна для
    /// повторной попытки.
    @discardableResult
    func confirmDelete() async -> Bool {
        guard !deletingAccount else { return false }
        deletingAccount = true
        deleteError = nil
        defer { deletingAccount = false }

        if needsAppleRevocation() {
            do {
                try await revoker()
            } catch AuthServiceError.cancelled {
                // Закрыл окно Apple — передумал, не ошибка.
                showDeleteConfirm = false
                return false
            } catch {
                showDeleteConfirm = false
                deleteError = AppLocaleStore.strings.profile.appleRevokeError
                return false
            }
        }

        do {
            try await deleter()
            showDeleteConfirm = false
            return true
        } catch {
            showDeleteConfirm = false
            deleteError = AppLocaleStore.strings.profile.deleteAccountError
            return false
        }
    }
}
