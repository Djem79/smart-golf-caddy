// ios/SmartGolfCaddy/Views/GroupLobbyView.swift
// Заглушка (Task 2, Фаза 3a) — лобби группового раунда: код, список игроков,
// старт хостом. Полная реализация — Task 3.
import SwiftUI

struct GroupLobbyView: View {
    let roundId: String

    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 40))
                .foregroundStyle(DSColor.primary)
            Text("Лобби группового раунда")
                .font(DSFont.titleLG)
                .foregroundStyle(DSColor.onSurface)
            Text("Раунд создан. Экран лобби (код приглашения, список игроков, старт) появится позже.")
                .font(DSFont.bodyMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.screenPadding)
            DSButton(title: "На главную", style: .secondary) { router.goHome() }
                .padding(.horizontal, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.surface)
        .navigationTitle("Лобби")
        .navigationBarTitleDisplayMode(.inline)
    }
}
