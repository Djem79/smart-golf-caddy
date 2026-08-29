// ios/SmartGolfCaddyTests/AppleSignInTests.swift
// Sign in with Apple — подготовка (App Store 4.8), capability не включена
// (нет платного аккаунта разработчика), поэтому все тесты — на моках и
// не трогают сеть/Firebase/реальную авторизацию:
//   - SHA-256 от raw-nonce считается верно и уходит в запрос Apple именно
//     хэшем (не raw) — testConfigureAppleRequestPutsHashNotRawInNonce;
//   - randomNonce даёт криптостойкую строку нужной длины и алфавита;
//   - отмена (ASAuthorizationError.canceled) не порождает сообщение об
//     ошибке — testCancelledResultThrowsCancelledWithoutTouchingFirebase +
//     SessionViewModel-часть в SessionViewModelTests;
//   - appleDisplayName отдаёт имя только когда Apple его прислала (первая
//     авторизация) и nil на повторных — вместе с идемпотентной записью
//     ensureProfile (уже переиспользуется от Google, см. AuthService.swift)
//     это и есть гарантия "не затираем сохранённое имя пустым".
//
// `import AuthenticationServices` в тесте — тот же системный UI-фреймворк,
// не Firebase; тест-таргету он доступен без дополнительных зависимостей
// в project.yml (как и остальные системные SDK).
import AuthenticationServices
import XCTest
@testable import SmartGolfCaddy

final class AppleSignInTests: XCTestCase {

    // MARK: - nonce / SHA-256

    func testSha256KnownVectors() {
        // Стандартные тестовые векторы SHA-256.
        XCTAssertEqual(
            AuthService.sha256(""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        XCTAssertEqual(
            AuthService.sha256("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testRandomNonceLengthAndAlphabet() {
        let nonce = AuthService.randomNonce(length: 32)
        XCTAssertEqual(nonce.count, 32)
        let allowed = CharacterSet(
            charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"
        )
        XCTAssertTrue(nonce.unicodeScalars.allSatisfy { allowed.contains($0) })
    }

    func testRandomNonceIsNotDeterministic() {
        // Криптостойкий источник — два вызова не должны совпасть
        // (астрономически маловероятно при 32 символах из ~70-символьного
        // алфавита; свидетельствует, что мы не забыли заменить рандом на
        // константу при рефакторинге).
        XCTAssertNotEqual(AuthService.randomNonce(), AuthService.randomNonce())
    }

    // MARK: - Запрос к Apple получает ХЭШ, не raw

    func testConfigureAppleRequestPutsHashNotRawInNonce() {
        let raw = "fixed-raw-nonce-for-test"
        let request = ASAuthorizationAppleIDProvider().createRequest()

        AuthService.configureAppleRequest(request, rawNonce: raw)

        XCTAssertEqual(request.nonce, AuthService.sha256(raw))
        XCTAssertNotEqual(request.nonce, raw)   // не raw напрямую
        XCTAssertEqual(Set(request.requestedScopes ?? []), Set([.fullName, .email]))
    }

    // MARK: - Отмена — не ошибка, не трогает Firebase

    func testCancelledResultThrowsCancelledWithoutTouchingFirebase() async {
        let cancelled = NSError(
            domain: ASAuthorizationErrorDomain,
            code: ASAuthorizationError.canceled.rawValue
        )
        do {
            // .failure ветка возвращается ДО обращения к Auth.auth() —
            // безопасно вызывать без сконфигурированного Firebase.
            try await AuthService.signInWithApple(result: .failure(cancelled), rawNonce: "irrelevant")
            XCTFail("expected AuthServiceError.cancelled")
        } catch AuthServiceError.cancelled {
            // ok — и errorDescription для неё nil (не покажет текст ошибки)
            XCTAssertNil(AuthServiceError.cancelled.errorDescription)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testOtherAuthorizationFailureMapsToGenericAppleError() async {
        let unknown = NSError(
            domain: ASAuthorizationErrorDomain,
            code: ASAuthorizationError.unknown.rawValue
        )
        do {
            try await AuthService.signInWithApple(result: .failure(unknown), rawNonce: "irrelevant")
            XCTFail("expected AuthServiceError.appleSignInFailed")
        } catch AuthServiceError.appleSignInFailed {
            XCTAssertEqual(
                AuthServiceError.appleSignInFailed.errorDescription,
                AppLocaleStore.strings.auth.appleSignInError
            )
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - Имя: только при первой авторизации

    func testAppleDisplayNameFormatsFullNameOnFirstAuthorization() {
        var components = PersonNameComponents()
        components.givenName = "John"
        components.familyName = "Appleseed"

        XCTAssertEqual(AuthService.appleDisplayName(from: components), "John Appleseed")
    }

    func testAppleDisplayNameNilWhenAppleOmitsIt() {
        // Повторный вход: Apple не присылает fullName вовсе.
        XCTAssertNil(AuthService.appleDisplayName(from: nil))
    }

    func testAppleDisplayNameNilForEmptyComponents() {
        // Защита от пустой (но не nil) структуры — не должны получить
        // пустую строку, которая потом ушла бы как "имя" в ensureProfile.
        XCTAssertNil(AuthService.appleDisplayName(from: PersonNameComponents()))
    }
}
