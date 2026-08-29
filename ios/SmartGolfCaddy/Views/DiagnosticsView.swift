// ios/SmartGolfCaddy/Views/DiagnosticsView.swift
// DEBUG-only: проверяет канал app → App Check → callable. Ожидаемый
// успех: joinLobbyByCode с несуществующим кодом возвращает roundId: null.
// Ошибка unauthenticated = App Check не пропустил (проверить debug token).
// Не подключён к UI с Фазы 2a; для проверки канала подключить временно в HomeView (#if DEBUG)
import FirebaseFunctions
import SwiftUI

struct DiagnosticsView: View {
    @Environment(LocaleManager.self) private var lm
    @State private var status: String?
    @State private var running = false

    private var statusText: String { status ?? lm.t.diagnostics.checkNotRun }

    var body: some View {
        VStack(spacing: 8) {
            Button {
                Task { await runCheck() }
            } label: {
                Label(lm.t.diagnostics.checkButton, systemImage: "antenna.radiowaves.left.and.right")
                    .font(DSFont.labelLG)
                    .frame(minHeight: DS.touchTarget)
            }
            .disabled(running)
            Text(statusText)
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
                status = lm.t.diagnostics.unexpectedResponse(String(describing: result.data))
                return
            }
            if data["roundId"] is NSNull || data["roundId"] == nil {
                status = lm.t.diagnostics.channelOk
            } else {
                status = lm.t.diagnostics.unexpectedResponse(String(describing: result.data))
            }
        } catch {
            let ns = error as NSError
            if ns.domain == FunctionsErrorDomain,
               ns.code == FunctionsErrorCode.unauthenticated.rawValue {
                status = lm.t.diagnostics.appCheckRejected
            } else {
                status = lm.t.diagnostics.errorPrefix(error.localizedDescription)
            }
        }
    }
}
