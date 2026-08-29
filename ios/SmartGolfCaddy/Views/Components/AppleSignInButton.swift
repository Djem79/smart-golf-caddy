// ios/SmartGolfCaddy/Views/Components/AppleSignInButton.swift
// Sign in with Apple (App Store 4.8 — обязательная приватная альтернатива
// Google, раз в приложении есть Google-вход). Capability ещё не включена
// (нет платного аккаунта разработчика) — компилируется и рендерится
// нормально, но реальная авторизация в рантайме упадёт до апгрейда; см.
// docs/superpowers/plans/2026-08-29-sign-in-with-apple.md.
//
// `import AuthenticationServices` здесь допустим по той же причине, что
// и в AuthService.swift (см. комментарий там): системный UI-фреймворк
// уровня "нативная кнопка входа", не Firebase — это второе (и последнее)
// разрешённое место для этого импорта. Сама вью НЕ импортирует
// Firebase/GoogleSignIn — только зовёт AuthService.signInWithApple(...).
import AuthenticationServices
import SwiftUI

/// Нативный SwiftUI-контрол HIG: логотип и надпись («Sign in with
/// Apple» и т.п.) даёт система в текущей локали устройства — свои
/// переводы запрещены документацией Apple, поэтому в `Strings`/
/// `LocaleManager` этот текст не заведён.
struct AppleSignInButton: View {
    @Environment(SessionViewModel.self) private var session
    // Raw-nonce живёт здесь (не внутри AuthService), потому что должен
    // пережить время между onRequest (когда генерируется и хэш уходит в
    // запрос Apple) и onCompletion (когда raw уходит в Firebase) —
    // единственная область, которая точно жива весь этот интервал,
    // это сама вью кнопки.
    @State private var rawNonce = ""

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            guard !session.isSigningIn else { return }
            session.beginSigningIn()
            let nonce = AuthService.randomNonce()
            rawNonce = nonce
            // SHA-256 от raw уходит в Apple; raw сам остаётся в rawNonce
            // и уйдёт в Firebase только в onCompletion ниже — см.
            // AuthService.configureAppleRequest.
            AuthService.configureAppleRequest(request, rawNonce: nonce)
        } onCompletion: { result in
            Task {
                do {
                    // Raw (не хэш) — сюда, в credential для Firebase.
                    try await AuthService.signInWithApple(result: result, rawNonce: rawNonce)
                    session.finishSigningIn(error: nil)
                } catch {
                    // AuthServiceError.cancelled гасится тихо внутри
                    // finishSigningIn — паритет с обработкой отмены
                    // Google-входа в SessionViewModel.signIn().
                    session.finishSigningIn(error: error)
                }
            }
        }
        // Стиль — чёрный. AuthView светлый (DSColor.surface = #F9F9F9),
        // не тёмно-зелёный: белая или white-outline кнопка потерялась бы
        // на этом фоне. Чёрный — контрастнее всего на светлом экране и
        // не спорит цветом с зелёной primary-кнопкой Google (различие
        // через яркость/цвет самой кнопки, а не перекраску — которую
        // Apple как раз запрещает).
        .signInWithAppleButtonStyle(.black)
        // Радиус = половина высоты — та же капсула, что у остальных
        // кнопок экрана (Google-кнопка в AuthView, DSButton). HIG прямо
        // разрешает подгонять радиус под остальные кнопки приложения,
        // лишь бы кнопка не была меньше минимума 30×140pt — наш
        // touchTarget (48pt) выше минимума с запасом.
        .cornerRadius(DS.touchTarget / 2)
        .frame(maxWidth: .infinity)
        .frame(minHeight: DS.touchTarget)
        .disabled(session.isSigningIn)
        .opacity(session.isSigningIn ? 0.6 : 1)
    }
}
