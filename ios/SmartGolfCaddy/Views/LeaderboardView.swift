// ios/SmartGolfCaddy/Views/LeaderboardView.swift
// Порт Leaderboard.tsx: живая таблица результатов группового раунда
// (stroke/match). Пуш-экран поверх HoleTracker — стандартный back (как
// MyBagView/CourseSearchView), без кастомного toolbar.
import SwiftUI

struct LeaderboardView: View {
    let roundId: String

    @Environment(AppRouter.self) private var router
    @State private var model = LeaderboardViewModel()

    var body: some View {
        Group {
            if let round = model.round {
                content(round)
            } else if let loadError = model.loadError {
                VStack(spacing: 16) {
                    Text(loadError)
                        .font(DSFont.bodyMD)
                        .foregroundStyle(DSColor.error)
                        .multilineTextAlignment(.center)
                    DSButton(title: "На главную", style: .secondary) { router.goHome() }
                        .padding(.horizontal, 48)
                }
                .padding(DS.screenPadding)
            } else {
                ProgressView("Загрузка...")
            }
        }
        .background(DSColor.surface)
        .navigationTitle("Таблица")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.start(roundId: roundId) }
        .onChange(of: model.round?.status) { _, status in
            guard status == .finished else { return }
            router.replaceLast(.results(roundId: roundId))
        }
    }

    private var isMatchPlay: Bool {
        guard let round = model.round else { return false }
        return round.playMode == .match && round.playerIds.count == 2
    }

    private var matchStatus: MatchPlayStatus? {
        guard let round = model.round, isMatchPlay else { return nil }
        return Scoring.matchPlayStatus(round: round, uidA: round.playerIds[0], uidB: round.playerIds[1])
    }

    private func statusText(_ round: Round) -> String {
        switch round.status {
        case .lobby: return "Лобби (ещё не начали)"
        case .finished: return "Раунд завершён"
        case .active: return "\(round.totalHoles) \(pluralRu(round.totalHoles, "лунка", "лунки", "лунок"))"
        }
    }

    private func content(_ round: Round) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                header(round)
                if isMatchPlay, let matchStatus { matchCard(round, matchStatus) }
                list(round)
            }
        }
    }

    private func header(_ round: Round) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(DSColor.onPrimary)
                .frame(width: 40, height: 40)
                .background(DSColor.onPrimary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(round.courseName)
                    .font(DSFont.labelMD)
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(DSColor.onPrimary.opacity(0.7))
                    .lineLimit(1)
                (Text(statusText(round))
                    + Text(isMatchPlay ? " · Match 1 v 1" : ""))
                    .font(DSFont.titleLG)
                    .foregroundStyle(DSColor.onPrimary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.screenPadding)
        .padding(.vertical, 16)
        .background(
            LinearGradient(colors: [DSColor.primaryContainer, DSColor.primary],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private func matchCard(_ round: Round, _ status: MatchPlayStatus) -> some View {
        VStack(spacing: 4) {
            Text("MATCH STATUS")
                .font(DSFont.labelMD)
                .tracking(1.5)
                .foregroundStyle(DSColor.onSurfaceVariant)
            Text(status.label)
                .font(DSFont.displayLG)
                .foregroundStyle(DSColor.primary)
                .monospacedDigit()
            Text(status.leaderUid.flatMap { round.players[$0]?.name }.map { "Ведёт: \($0)" } ?? "Игроки на равных")
                .font(DSFont.labelLG)
                .foregroundStyle(DSColor.onSurface)
            if status.closed {
                Label("Матч решён", systemImage: "checkmark")
                    .font(DSFont.labelMD)
                    .foregroundStyle(DSColor.primary)
                    .padding(.top, 4)
            }
            Text("Сыграно: \(status.holesPlayed) · Осталось: \(status.holesRemaining)")
                .font(DSFont.labelMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(DSColor.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: DS.cornerRadius).stroke(DSColor.outlineVariant.opacity(0.3)))
        .padding(.horizontal, DS.screenPadding)
        .padding(.top, 16)
    }

    private func list(_ round: Round) -> some View {
        let entries = Scoring.leaderboard(round: round)
        return VStack(spacing: 8) {
            HStack {
                Text("#").frame(width: 28, alignment: .leading)
                Text("Игрок").frame(maxWidth: .infinity, alignment: .leading)
                Text("К пару").frame(width: 64, alignment: .trailing)
            }
            .font(DSFont.labelMD)
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(DSColor.onSurfaceVariant)
            .padding(.horizontal, 12)

            if entries.isEmpty {
                Text("Игроков пока нет")
                    .font(DSFont.bodyMD)
                    .foregroundStyle(DSColor.onSurfaceVariant)
                    .padding(.top, 32)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                    row(entry, position: idx + 1, totalHoles: round.totalHoles)
                }
            }
        }
        .padding(.horizontal, DS.screenPadding)
        .padding(.vertical, 16)
    }

    private func row(_ entry: LeaderboardEntry, position: Int, totalHoles: Int) -> some View {
        let isMe = entry.uid == AuthService.currentUserId
        return HStack(spacing: 12) {
            Text("\(position)")
                .font(DSFont.titleLG)
                .foregroundStyle(DSColor.onSurface)
                .monospacedDigit()
                .frame(width: 28, alignment: .leading)
            avatarCircle(entry.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(isMe ? "\(entry.name) (вы)" : entry.name)
                    .font(DSFont.bodyMD)
                    .foregroundStyle(DSColor.onSurface)
                    .lineLimit(1)
                Text("\(entry.thru > 0 ? "\(entry.totalScore)" : "—") удар. · \(entry.thru)/\(totalHoles)")
                    .font(DSFont.labelMD)
                    .foregroundStyle(DSColor.onSurfaceVariant)
            }
            Spacer(minLength: 4)
            diffPill(entry)
        }
        .padding(12)
        .background(isMe ? DSColor.primaryContainer.opacity(0.1) : DSColor.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DS.cornerRadius)
                .stroke(isMe ? DSColor.primary : DSColor.outlineVariant.opacity(0.3))
        )
    }

    private func avatarCircle(_ name: String) -> some View {
        Text(initials(name))
            .font(DSFont.labelMD)
            .foregroundStyle(DSColor.onPrimary)
            .frame(width: 32, height: 32)
            .background(DSColor.primaryContainer)
            .clipShape(Circle())
    }

    private func initials(_ name: String) -> String {
        let parts = name.trimmingCharacters(in: .whitespaces).split(separator: " ")
        if parts.isEmpty { return "—" }
        if parts.count == 1 { return String(parts[0].prefix(2)).uppercased() }
        let first = parts[0].first.map(String.init) ?? ""
        let last = parts[parts.count - 1].first.map(String.init) ?? ""
        return (first + last).uppercased()
    }

    // Порт formatDiff: 'E' на нуле, '+N'/'-N' иначе, «—» для несыгравших.
    private func formatDiff(_ d: Int, thru: Int) -> String {
        if thru == 0 { return "—" }
        if d == 0 { return "E" }
        if d > 0 { return "+\(d)" }
        return "\(d)"
    }

    private func diffPill(_ entry: LeaderboardEntry) -> some View {
        let filled = entry.thru > 0 && entry.scoreDiff != 0
        let bordered = entry.thru > 0 && entry.scoreDiff == 0
        let background = filled ? Color(hex: Score.color(entry.scoreDiff)) : Color.clear
        let foreground = filled ? Color(hex: Score.onColor(entry.scoreDiff)) : DSColor.onSurface
        let direction = Score.direction(entry.scoreDiff)
        let dirIcon = direction == .under ? "chart.line.downtrend.xyaxis"
            : direction == .over ? "chart.line.uptrend.xyaxis" : "minus"
        return HStack(spacing: 4) {
            if entry.thru > 0 {
                Image(systemName: dirIcon).font(.system(size: 11, weight: .bold))
            }
            Text(formatDiff(entry.scoreDiff, thru: entry.thru))
        }
        .font(DSFont.titleLG)
        .monospacedDigit()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(width: 64)
        .background(background)
        .foregroundStyle(foreground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(bordered ? DSColor.outlineVariant : .clear)
        )
    }
}
