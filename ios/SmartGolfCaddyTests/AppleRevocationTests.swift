// ios/SmartGolfCaddyTests/AppleRevocationTests.swift
// TN3194: при удалении аккаунта токен «Входа с Apple» отзывается ДО
// вызова deleteAccount. Capability Apple не включена (нет платного
// аккаунта разработчика), поэтому живой ASAuthorizationController здесь
// не поднимается — проверяются:
//   - порядок и гейты в AccountViewModel (revoker → deleter; провал/отмена
//     отзыва не доходят до удаления);
//   - чистые отображения AppleAuthorizationCodeRequester (отмена → тихая
//     .cancelled, прочее → .appleRevokeFailed; не-Apple credential →
//     .missingToken).
import AuthenticationServices
import XCTest
@testable import SmartGolfCaddy

final class AppleRevocationTests: XCTestCase {

    // MARK: - AccountViewModel: порядок revoke → delete

    @MainActor
    func testAppleLinkedAccountRevokesBeforeDeleting() async {
        var order: [String] = []
        let model = AccountViewModel(
            needsAppleRevocation: { true },
            revoker: { order.append("revoke") },
            deleter: { order.append("delete") }
        )
        model.showDeleteConfirm = true

        let success = await model.confirmDelete()

        XCTAssertTrue(success)
        XCTAssertEqual(order, ["revoke", "delete"])
        XCTAssertFalse(model.showDeleteConfirm)
        XCTAssertNil(model.deleteError)
    }

    @MainActor
    func testGoogleOnlyAccountSkipsRevocation() async {
        var revoked = false
        let model = AccountViewModel(
            needsAppleRevocation: { false },
            revoker: { revoked = true },
            deleter: {}
        )

        let success = await model.confirmDelete()

        XCTAssertTrue(success)
        XCTAssertFalse(revoked)
    }

    @MainActor
    func testFailedRevocationLeavesAccountUntouchedWithAppleSpecificError() async {
        var deleted = false
        let model = AccountViewModel(
            needsAppleRevocation: { true },
            revoker: { throw AuthServiceError.appleRevokeFailed },
            deleter: { deleted = true }
        )
        model.showDeleteConfirm = true

        let success = await model.confirmDelete()

        XCTAssertFalse(success)
        XCTAssertFalse(deleted)
        XCTAssertFalse(model.showDeleteConfirm)
        XCTAssertEqual(model.deleteError, AppLocaleStore.strings.profile.appleRevokeError)
        XCTAssertFalse(model.deletingAccount)   // снова доступно для повтора
    }

    @MainActor
    func testCancelledAppleSheetIsSilentAndDeletesNothing() async {
        var deleted = false
        let model = AccountViewModel(
            needsAppleRevocation: { true },
            revoker: { throw AuthServiceError.cancelled },
            deleter: { deleted = true }
        )
        model.showDeleteConfirm = true

        let success = await model.confirmDelete()

        XCTAssertFalse(success)
        XCTAssertFalse(deleted)
        XCTAssertFalse(model.showDeleteConfirm)
        XCTAssertNil(model.deleteError)          // передумал — не ошибка
    }

    // MARK: - AppleAuthorizationCodeRequester: чистые отображения

    func testCancelledAuthorizationMapsToSilentCancelled() {
        let cancelled = NSError(
            domain: ASAuthorizationErrorDomain,
            code: ASAuthorizationError.canceled.rawValue
        )
        let mapped = AppleAuthorizationCodeRequester.mapAuthorizationError(cancelled)
        guard case .cancelled = mapped else {
            return XCTFail("expected .cancelled, got \(mapped)")
        }
        XCTAssertNil(mapped.errorDescription)
    }

    func testOtherAuthorizationFailureMapsToRevokeFailed() {
        let failed = NSError(
            domain: ASAuthorizationErrorDomain,
            code: ASAuthorizationError.failed.rawValue
        )
        let mapped = AppleAuthorizationCodeRequester.mapAuthorizationError(failed)
        guard case .appleRevokeFailed = mapped else {
            return XCTFail("expected .appleRevokeFailed, got \(mapped)")
        }
        XCTAssertEqual(mapped.errorDescription, AppLocaleStore.strings.profile.appleRevokeError)
    }

    func testNonAppleCredentialYieldsMissingToken() {
        // ASPasswordCredential — единственный ASAuthorizationCredential,
        // который можно построить без живой авторизации.
        let credential = ASPasswordCredential(user: "u", password: "p")
        XCTAssertThrowsError(
            try AppleAuthorizationCodeRequester.extractAuthorizationCode(from: credential)
        ) { error in
            guard case AuthServiceError.missingToken = error else {
                return XCTFail("expected .missingToken, got \(error)")
            }
        }
    }
}
