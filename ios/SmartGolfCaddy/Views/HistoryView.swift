import SwiftUI

struct HistoryView: View {
    @State private var model = HistoryViewModel()

    private var currentUserId: String? { AuthService.currentUserId }

    var body: some View {
        Group {
            if model.loadError {
                errorState
            } else if model.loading {
                ProgressView("Загрузка...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.rounds.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(DSColor.surface)
        .navigationTitle("История раундов")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let uid = currentUserId { await model.load(userId: uid) }
        }
        .refreshable {
            if let uid = currentUserId { await model.load(userId: uid) }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(model.rounds) { round in
                    NavigationLink(value: Route.results(roundId: round.id)) {
                        row(round)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DS.screenPadding)
        }
    }

    private func row(_ round: Round) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(round.courseName)
                    .font(DSFont.bodyMD)
                    .foregroundStyle(DSColor.onSurface)
                    .lineLimit(1)
                Text(subtitle(round))
                    .font(DSFont.labelLG)
                    .foregroundStyle(DSColor.onSurfaceVariant)
            }
            Spacer()
            if let uid = currentUserId {
                let totals = Scoring.playerTotals(round: round, userId: uid)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(totals.totalScore)")
                        .font(DSFont.titleLG)
                        .foregroundStyle(DSColor.primary)
                        .monospacedDigit()
                    Text("\(totals.scoreDiff >= 0 ? "+" : "")\(totals.scoreDiff)")
                        .font(DSFont.labelMD)
                        .foregroundStyle(DSColor.onSurfaceVariant)
                        .monospacedDigit()
                }
            }
        }
        .padding(14)
        .background(DSColor.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.cornerRadius)
                .stroke(DSColor.outlineVariant.opacity(0.25))
        )
    }

    private func subtitle(_ round: Round) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        let date = formatter.string(from: round.createdAt)
        let players = round.players.count
        return "\(date) · \(round.totalHoles) \(pluralRu(round.totalHoles, "лунка", "лунки", "лунок")) · \(players) \(pluralRu(players, "игрок", "игрока", "игроков"))"
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "flag")
                .font(.system(size: 26))
                .foregroundStyle(DSColor.onSurfaceVariant)
                .frame(width: 56, height: 56)
                .background(DSColor.surfaceContainer)
                .clipShape(Circle())
            Text("Нет завершённых раундов")
                .font(DSFont.bodyMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorState: some View {
        VStack(spacing: 16) {
            Text("Не удалось загрузить историю")
                .font(DSFont.bodyMD)
                .foregroundStyle(DSColor.onSurface)
            DSButton(title: "Повторить", style: .secondary) {
                Task {
                    if let uid = currentUserId { await model.load(userId: uid) }
                }
            }
            .padding(.horizontal, 64)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
