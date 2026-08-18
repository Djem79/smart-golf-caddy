// ios/SmartGolfCaddy/Services/AuthService.swift
// Зеркало src/services/auth.ts: Google-вход + создание профиля при
// первом входе. Наружу отдаёт только uid и замыкание-отписку — слои
// выше не видят типов Firebase.
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn
import UIKit

enum AuthServiceError: LocalizedError {
    case noPresenter
    case missingToken
    case cancelled   // пользователь закрыл окно входа — не показывается как ошибка

    var errorDescription: String? {
        switch self {
        case .noPresenter: return "Не найден корневой экран для входа"
        case .missingToken: return "Google не вернул токен — попробуйте ещё раз"
        case .cancelled: return nil
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
