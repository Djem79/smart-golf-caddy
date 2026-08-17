// ios/SmartGolfCaddy/Views/DiagnosticsView.swift
// DEBUG-only: проверяет канал app → App Check → callable. Ожидаемый
// успех: joinLobbyByCode с несуществующим кодом возвращает roundId: null.
// Ошибка unauthenticated = App Check не пропустил (проверить debug token).
import FirebaseFunctions
import SwiftUI

struct DiagnosticsView: View {
    @State private var status = "Проверка связи не запускалась"
    @State private var running = false

    var body: some View {
        VStack(spacing: 8) {
            Button {
                Task { await runCheck() }
            } label: {
                Label("Проверить связь с сервером", systemImage: "antenna.radiowaves.left.and.right")
                    .font(DSFont.labelLG)
                    .frame(minHeight: DS.touchTarget)
            }
            .disabled(running)
            Text(status)
                .font(DSFont.labelMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
                .multilineTextAlignment(.center)
        }
        .padding(DS.screenPadding)
    }

    private func runCheck() async {
        running = true
        defer { running = false }
        do {
            let payload = try callableDict(JoinLobbyInput(code: "ZZZZZZ", playerInfo: nil))
            let result = try await FirebaseService.functions
                .httpsCallable("joinLobbyByCode").call(payload)
            guard let data = result.data as? [String: Any] else {
                status = "Неожиданный ответ: \(String(describing: result.data))"
                return
            }
            if data["roundId"] is NSNull || data["roundId"] == nil {
                status = "Сервер отвечает, App Check пропускает. Канал работает."
            } else {
                status = "Неожиданный ответ: \(String(describing: result.data))"
            }
        } catch {
            let ns = error as NSError
            if ns.domain == FunctionsErrorDomain,
               ns.code == FunctionsErrorCode.unauthenticated.rawValue {
                status = "App Check отклонил вызов — зарегистрируйте debug token в консоли Firebase"
            } else {
                status = "Ошибка: \(error.localizedDescription)"
            }
        }
    }
}
