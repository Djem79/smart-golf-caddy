// ios/SmartGolfCaddy/Services/AccountService.swift
// Task 3, фаза 3d-1 (App Store 5.1.1(v)): вызов callable deleteAccount.
// Payload пустой — uid сервер берёт из проверенного auth-токена, никогда
// из клиента (см. DeleteAccountInput в CallableContracts.swift).
//
// НЕ делает signOut — это ответственность вызывающей стороны
// (AccountViewModel/ProfileView), чтобы неудачное удаление никогда не
// разлогинивало пользователя с данными, которые могли не удалиться.
import Foundation

enum AccountService {
    static func deleteAccount() async throws {
        let payload = try callableDict(DeleteAccountInput())
        _ = try await FirebaseService.functions.httpsCallable("deleteAccount").call(payload)
    }
}
