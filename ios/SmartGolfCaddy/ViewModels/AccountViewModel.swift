// ios/SmartGolfCaddy/ViewModels/AccountViewModel.swift
// Task 3, фаза 3d-1: удаление аккаунта из профиля (App Store 5.1.1(v)).
// `deleter` инжектируется — тесты подменяют сеть (образец JoinGameViewModel).
// Эта VM НЕ делает signOut/навигацию сама — confirmDelete() возвращает
// успех/провал, ProfileView вызывает session.signOut() ТОЛЬКО при true.
// Так неудачное удаление (данные могли не удалиться) никогда не
// разлогинивает пользователя — паритет с web/services/account.ts.
import Foundation
import Observation

@Observable
@MainActor
final class AccountViewModel {
    var showDeleteConfirm = false
    var deletingAccount = false
    var deleteError: String?

    private let deleter: () async throws -> Void

    convenience init() {
        self.init(deleter: { try await AccountService.deleteAccount() })
    }

    init(deleter: @escaping () async throws -> Void) {
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
        do {
            try await deleter()
            showDeleteConfirm = false
            return true
        } catch {
            showDeleteConfirm = false
            deleteError = "Не удалось удалить аккаунт. Проверьте соединение и попробуйте ещё раз."
            return false
        }
    }
}
