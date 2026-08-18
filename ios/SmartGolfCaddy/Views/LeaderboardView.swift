// ios/SmartGolfCaddy/Views/LeaderboardView.swift
// Заглушка (Task 2, Фаза 3a) — живая таблица результатов группового раунда
// (stroke/match). Полная реализация — Task 5.
import SwiftUI

struct LeaderboardView: View {
    let roundId: String

    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "trophy")
                .font(.system(size: 40))
                .foregroundStyle(DSColor.primary)
            Text("Таблица результатов")
                .font(DSFont.titleLG)
                .foregroundStyle(DSColor.onSurface)
            Text("Живая таблица результатов раунда появится позже.")
                .font(DSFont.bodyMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.screenPadding)
            DSButton(title: "На главную", style: .secondary) { router.goHome() }
                .padding(.horizontal, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.surface)
        .navigationTitle("Таблица")
        .navigationBarTitleDisplayMode(.inline)
    }
}
