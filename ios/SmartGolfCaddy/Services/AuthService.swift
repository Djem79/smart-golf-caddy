// ios/SmartGolfCaddy/Services/AuthService.swift
// Зеркало src/services/auth.ts: Google/Apple-вход + создание профиля при
// первом входе. Наружу отдаёт только uid и замыкание-отписку — слои
// выше не видят типов Firebase.
//
// `import AuthenticationServices` здесь допустим наравне с
// `import GoogleSignIn`: это системный UI-фреймворк уровня "нативная
// кнопка входа" (как GoogleSignIn), не Firebase — правило ios/CLAUDE.md
// "import Firebase*/GoogleSignIn только в Services/" распространяется и
// на него. Второе разрешённое место — файл кнопки
// (Views/Components/AppleSignInButton.swift), поскольку SwiftUI-обёртку
// `SignInWithAppleButton` и её callback-типы нельзя объявить без этого
// импорта, а сама кнопка не должна тянуть FirebaseAuth в View-слой.
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn
import UIKit

enum AuthServiceError: LocalizedError {
    case noPresenter
    case missingToken
    case cancelled   // пользователь закрыл окно входа — не показывается как ошибка
    // Тот же email уже привязан к другому провайдеру входа (Firebase
    // `accountExistsWithDifferentCredential`). Полноценное связывание
    // аккаунтов — веб-задача; здесь только понятное сообщение.
    case accountExistsWithDifferentCredential
    case appleSignInFailed   // прочие отказы Apple/Firebase — общий текст

    var errorDescription: String? {
        switch self {
        case .noPresenter: return AppLocaleStore.strings.auth.noPresenterError
        case .missingToken: return AppLocaleStore.strings.auth.missingTokenError
        case .cancelled: return nil
        case .accountExistsWithDifferentCredential: return AppLocaleStore.strings.auth.accountExistsError
        case .appleSignInFailed: return AppLocaleStore.strings.auth.appleSignInError
        }
    }
}

@MainActor
enum AuthService {
    static var currentUserId: String? { Auth.auth().currentUser?.uid }
    static var currentUserEmail: String? { Auth.auth().currentUser?.email }

    static func subscribe(_ callback: @escaping (String?) -> Void) -> () -> Void {
        let handle = Auth.auth().addStateDidChangeListener { _, user in
            callback(user?.uid)
        }
        return { Auth.auth().removeStateDidChangeListener(handle) }
    }

    static func signInWithGoogle() async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthServiceError.missingToken
        }
        guard let presenter = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first else {
            throw AuthServiceError.noPresenter
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        } catch let error as NSError
            where error.domain == kGIDSignInErrorDomain
                && error.code == GIDSignInError.canceled.rawValue {
            throw AuthServiceError.cancelled
        }
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthServiceError.missingToken
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        let authResult = try await Auth.auth().signIn(with: credential)
        try await ensureProfile(
            uid: authResult.user.uid,
            name: authResult.user.displayName,
            avatar: authResult.user.photoURL?.absoluteString
        )
    }

    // MARK: - Sign in with Apple (App Store 4.8 — обязателен как
    // равноценная приватная альтернатива Google). Capability пока не
    // включена (нет платного аккаунта разработчика) — код собирается,
    // но реальная авторизация упадёт в рантайме до апгрейда; см.
    // docs/superpowers/plans/2026-08-29-sign-in-with-apple.md.

    /// Криптостойкий raw-nonce (`SecRandomCopyBytes`). В запрос Apple
    /// уходит его SHA-256 (`configureAppleRequest`), а в Firebase —
    /// именно ЭТОТ raw (`OAuthProvider.appleCredential(rawNonce:)`).
    /// Перепутать местами = проверка подписи не проходит.
    // nonisolated: чистые вычисления без обращения к MainActor-состоянию
    // (Auth.auth() и т.п.) — тестам и вызывающей стороне не нужно быть на
    // MainActor, чтобы их вызвать.
    nonisolated static func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array(
            "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"
        )
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
            for random in randoms where remaining > 0 {
                // Отбрасываем байты >= charset.count, чтобы не давать
                // символам из начала алфавита систематическое
                // преимущество (модульное смещение).
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    nonisolated static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }

    /// Настраивает запрос Apple: запрашивает имя/почту (доступны только
    /// при ПЕРВОЙ авторизации — см. `appleDisplayName`) и кладёт в
    /// `nonce` именно ХЭШ, не raw-строку.
    nonisolated static func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest, rawNonce: String) {
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(rawNonce)
    }

    /// Apple присылает `fullName` ТОЛЬКО при первой авторизации — при
    /// повторных входах `components` будет `nil`/пустым. Вызывающая
    /// сторона обязана передать результат прямиком в `ensureProfile`,
    /// которая пишет профиль один раз и не перезаписывает существующее
    /// имя при повторном входе — так пустое значение с повторного входа
    /// никогда не затирает сохранённое.
    nonisolated static func appleDisplayName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatted = PersonNameComponentsFormatter()
            .string(from: components)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return formatted.isEmpty ? nil : formatted
    }

    /// `result` — прямиком из `SignInWithAppleButton.onCompletion`.
    /// Отказ пользователя (`ASAuthorizationError.canceled`) отображается
    /// как `.cancelled` ДО обращения к Firebase — паритет с обработкой
    /// `GIDSignInError.canceled` в `signInWithGoogle()`.
    static func signInWithApple(
        result: Result<ASAuthorization, Error>,
        rawNonce: String
    ) async throws {
        let authorization: ASAuthorization
        switch result {
        case .success(let value):
            authorization = value
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                throw AuthServiceError.cancelled
            }
            throw AuthServiceError.appleSignInFailed
        }
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let identityToken = appleIDCredential.identityToken,
            let idTokenString = String(data: identityToken, encoding: .utf8)
        else {
            throw AuthServiceError.missingToken
        }
        // Долговременный ключ личности — appleIDCredential.user (стабильный
        // Apple ID), НЕ email (может быть private-relay и не переиспользуется
        // Firebase как identity). Firebase сам ведёт этот маппинг внутри
        // credential ниже — здесь просто не полагаемся на email.
        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: rawNonce,
            fullName: appleIDCredential.fullName
        )
        let authResult: AuthDataResult
        do {
            authResult = try await Auth.auth().signIn(with: credential)
        } catch let error as NSError
            where error.domain == AuthErrorDomain
                && error.code == AuthErrorCode.accountExistsWithDifferentCredential.rawValue {
            throw AuthServiceError.accountExistsWithDifferentCredential
        }
        try await ensureProfile(
            uid: authResult.user.uid,
            name: appleDisplayName(from: appleIDCredential.fullName),
            avatar: authResult.user.photoURL?.absoluteString
        )
    }

    // Паритет signInWithGoogle из auth.ts: профиль создаётся один раз,
    // с каноничным bag (не legacy clubs).
    static func ensureProfile(uid: String, name: String?, avatar: String?) async throws {
        let ref = FirebaseService.db.collection("users").document(uid)
        let snapshot = try await ref.getDocument()
        guard !snapshot.exists else { return }
        try await ref.setData([
            "name": name ?? "Golfer",
            "avatar": avatar ?? "",
            "handicap": 0,
            "bag": Clubs.defaultBag.map { $0.firestoreData },
            "createdAt": FieldValue.serverTimestamp(),
        ])
    }

    static func signOut() throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
    }
}
