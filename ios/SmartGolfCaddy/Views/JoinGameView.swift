// ios/SmartGolfCaddy/Views/JoinGameView.swift
// Заглушка (Task 2, Фаза 3a) — вход в лобби по коду (ручной ввод или
// deep-link с уже известным `code`). Полная реализация — Task 4.
import SwiftUI

struct JoinGameView: View {
    let code: String?

    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 40))
                .foregroundStyle(DSColor.primary)
            Text("Присоединиться к игре")
                .font(DSFont.titleLG)
                .foregroundStyle(DSColor.onSurface)
            if let code {
                Text("Код лобби: \(code)")
                    .font(DSFont.bodyMD)
                    .foregroundStyle(DSColor.onSurfaceVariant)
            } else {
                Text("Ввод кода лобби появится позже.")
                    .font(DSFont.bodyMD)
                    .foregroundStyle(DSColor.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.screenPadding)
            }
            DSButton(title: "На главную", style: .secondary) { router.goHome() }
                .padding(.horizontal, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.surface)
        .navigationTitle("Присоединиться")
        .navigationBarTitleDisplayMode(.inline)
    }
}
