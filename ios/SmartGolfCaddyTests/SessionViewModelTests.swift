// ios/SmartGolfCaddyTests/SessionViewModelTests.swift
// Sign in with Apple (T1, App Store 4.8): AppleSignInButton не может call
// AuthService.signInWithApple(...) through SessionViewModel (тот параметр
// требует `import AuthenticationServices`, который в ViewModels/ не
// разрешён — см. комментарий в SessionViewModel.swift), поэтому кнопка
// сама зовёт AuthService и репортит результат сюда, в
// begin/finishSigningIn(error:). Эти тесты проверяют именно ту часть,
// что видна пользователю: отмена — без текста ошибки, прочее — с текстом.
import XCTest
@testable import SmartGolfCaddy

final class SessionViewModelTests: XCTestCase {

    @MainActor
    func testCancelledLeavesErrorMessageNilAndStopsSpinner() {
        let session = SessionViewModel()
        session.beginSigningIn()
        XCTAssertTrue(session.isSigningIn)

        session.finishSigningIn(error: AuthServiceError.cancelled)

        XCTAssertFalse(session.isSigningIn)
        XCTAssertNil(session.errorMessage)
    }

    @MainActor
    func testSuccessClearsSpinnerWithoutError() {
        let session = SessionViewModel()
        session.beginSigningIn()

        session.finishSigningIn(error: nil)

        XCTAssertFalse(session.isSigningIn)
        XCTAssertNil(session.errorMessage)
    }

    @MainActor
    func testAccountExistsShowsLinkingMessage() {
        let session = SessionViewModel()
        session.beginSigningIn()

        session.finishSigningIn(error: AuthServiceError.accountExistsWithDifferentCredential)

        XCTAssertFalse(session.isSigningIn)
        XCTAssertEqual(session.errorMessage, AppLocaleStore.strings.auth.accountExistsError)
    }

    @MainActor
    func testGenericFailureShowsGenericAppleMessage() {
        let session = SessionViewModel()
        session.beginSigningIn()

        session.finishSigningIn(error: AuthServiceError.appleSignInFailed)

        XCTAssertFalse(session.isSigningIn)
        XCTAssertEqual(session.errorMessage, AppLocaleStore.strings.auth.appleSignInError)
    }

    @MainActor
    func testBeginSigningInClearsPreviousError() {
        let session = SessionViewModel()
        session.errorMessage = "stale error from a previous attempt"

        session.beginSigningIn()

        XCTAssertNil(session.errorMessage)
        XCTAssertTrue(session.isSigningIn)
    }
}
