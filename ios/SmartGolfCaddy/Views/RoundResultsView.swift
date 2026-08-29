// ios/SmartGolfCaddy/Views/RoundResultsView.swift
import SwiftUI

struct RoundResultsView: View {
    let roundId: String

    @Environment(SessionViewModel.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(LocaleManager.self) private var lm
    @State private var model = RoundResultsViewModel()

    private var viewerBag: [BagClub] { session.profile?.resolvedBag ?? Clubs.defaultBag }

    /// Средняя дистанция клюшки в юнитах пользователя (профиль → ярды/метры).
    private func avgDistanceText(_ meters: Int) -> String {
        if session.profile?.units == .yd {
            return "\(Score.metersToYards(meters)) \(lm.t.common.yardsShort)"
        }
        return "\(meters) \(lm.t.common.metersShort)"
    }

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
                    DSButton(title: lm.t.common.goHome, style: .secondary) { router.goHome() }
                        .padding(.horizontal, 48)
                }
                .padding(DS.screenPadding)
            } else {
                ProgressView(lm.t.roundResults.loading)
            }
        }
        .background(DSColor.surface)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(lm.t.roundResults.title).font(DSFont.titleLG)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button { router.goHome() } label: { Image(systemName: "house") }
                    .accessibilityLabel(lm.t.common.goHome)
            }
        }
        .task { model.start(roundId: roundId) }
    }

    @ViewBuilder
    private func content(_ round: Round) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                hero(round)
                if round.playerIds.count > 1 { leaderboardSection(round) }
                clubUsageSection(round)
                scorecardSection(round)
                VStack(spacing: 10) {
                    DSButton(title: lm.t.roundResults.newRound, icon: "plus") {
                        router.startNewRound()
                    }
                    DSButton(title: lm.t.common.goHome, style: .secondary) { router.goHome() }
                }
                .padding(.horizontal, DS.screenPadding)
            }
            .padding(.bottom, 32)
        }
    }

    // Соло: свой результат; матч (2 игрока, match): статус; иначе — победитель.
    @ViewBuilder
    private func hero(_ round: Round) -> some View {
        let isSolo = round.playerIds.count == 1
        let isMatch = round.playMode == .match && round.playerIds.count == 2
        VStack(spacing: 8) {
            Image(systemName: isSolo ? "flag.fill" : "trophy.fill")
                .font(.system(size: 24))
                .foregroundStyle(DSColor.onPrimary)
                .frame(width: 48, height: 48)
                .background(DSColor.onPrimary.opacity(0.1))
                .clipShape(Circle())
            if isMatch {
                let status = Scoring.matchPlayStatus(round: round,
                                                     uidA: round.playerIds[0],
                                                     uidB: round.playerIds[1])
                Text(lm.t.roundResults.matchPlayUppercase)
                    .font(DSFont.labelLG).tracking(2.5)
                    .foregroundStyle(DSColor.onPrimary.opacity(0.7))
                Text(status.label)
                    .font(DSFont.displayLG)
                    .foregroundStyle(DSColor.onPrimary)
                    .monospacedDigit()
                Text(status.leaderUid.flatMap { round.players[$0]?.displayName } ?? lm.t.common.playersEven)
                    .font(DSFont.bodyMD)
                    .foregroundStyle(DSColor.onPrimary)
            } else if isSolo {
                let totals = Scoring.playerTotals(round: round, userId: round.playerIds[0])
                Text(lm.t.roundResults.yourResultUppercase)
                    .font(DSFont.labelLG).tracking(2.5)
                    .foregroundStyle(DSColor.onPrimary.opacity(0.7))
                Text("\(totals.totalScore) \(lm.t.roundResults.strokesShortDot)")
                    .font(DSFont.displayLG)
                    .foregroundStyle(DSColor.onPrimary)
                    .monospacedDigit()
                Text("\(totals.scoreDiff >= 0 ? "+" : "")\(totals.scoreDiff) (\(Score.label(totals.scoreDiff)))")
                    .font(DSFont.bodyMD)
                    .foregroundStyle(DSColor.onPrimary)
            } else {
                let winner = Scoring.leaderboard(round: round).first
                Text(lm.t.roundResults.winnerUppercase)
                    .font(DSFont.labelLG).tracking(2.5)
                    .foregroundStyle(DSColor.onPrimary.opacity(0.7))
                Text((winner?.thru ?? 0) > 0 ? (winner?.name ?? lm.t.common.unknown) : lm.t.common.unknown)
                    .font(DSFont.headlineLG)
                    .foregroundStyle(DSColor.onPrimary)
            }
            Text("\(round.courseName) · \(round.totalHoles) \(plural(round.totalHoles, lm.current, lm.t.common.holesWord))")
                .font(DSFont.labelMD)
                .foregroundStyle(DSColor.onPrimary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            LinearGradient(colors: [DSColor.primaryContainer, DSColor.primary],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private func leaderboardSection(_ round: Round) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(lm.t.roundResults.leaderboardSectionTitle)
            ForEach(Scoring.leaderboard(round: round)) { entry in
                HStack {
                    Text(entry.name)
                        .font(DSFont.bodyMD)
                        .foregroundStyle(DSColor.onSurface)
                        .lineLimit(1)
                    Spacer()
                    Text("\(entry.totalScore)")
                        .font(DSFont.titleLG)
                        .foregroundStyle(DSColor.onSurface)
                        .monospacedDigit()
                    scorePill(delta: entry.scoreDiff)
                }
                .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, DS.screenPadding)
    }

    private func clubUsageSection(_ round: Round) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(round.playerIds, id: \.self) { uid in
                let usage = Scoring.clubUsage(round: round, userId: uid)
                if !usage.isEmpty {
                    sectionTitle(round.playerIds.count == 1
                                 ? lm.t.roundResults.clubsTitle
                                 : lm.t.roundResults.clubsForPlayer(round.players[uid]?.displayName ?? ""))
                    FlowLayoutCompat(items: Array(usage.enumerated()), spacing: 6) { _, stat in
                        Text(stat.avgDistanceMeters > 0
                             ? "\(Clubs.label(for: stat.club, in: viewerBag)) · \(stat.count) (\(stat.percent)%) · \(lm.t.roundResults.avgAbbrev) \(avgDistanceText(stat.avgDistanceMeters))"
                             : "\(Clubs.label(for: stat.club, in: viewerBag)) · \(stat.count) (\(stat.percent)%)")
                            .font(DSFont.labelMD)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(DSColor.surfaceContainer)
                            .foregroundStyle(DSColor.onSurfaceVariant)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, DS.screenPadding)
    }

    // Скоркарта: горизонтальный скролл, ячейка лунки закрашена scoreColor.
    private func scorecardSection(_ round: Round) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(lm.t.roundResults.scorecardTitle)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        cell(lm.t.roundResults.holeColumnHeader, width: 72, header: true)
                        ForEach(round.holes, id: \.holeNumber) { hole in
                            cell("\(hole.holeNumber)", header: true)
                        }
                    }
                    HStack(spacing: 4) {
                        cell(lm.t.common.par, width: 72, header: true)
                        ForEach(round.holes, id: \.holeNumber) { hole in
                            cell("\(hole.par)")
                        }
                    }
                    ForEach(round.playerIds, id: \.self) { uid in
                        HStack(spacing: 4) {
                            cell(round.playerIds.count == 1 ? lm.t.roundResults.strokesRowHeader : (round.players[uid]?.displayName ?? ""), width: 72, header: true)
                            ForEach(round.holes, id: \.holeNumber) { hole in
                                let shots = hole.shots[uid]?.count ?? 0
                                if shots > 0 {
                                    cell("\(shots)",
                                         background: Color(hex: Score.color(shots - hole.par)),
                                         foreground: Color(hex: Score.onColor(shots - hole.par)))
                                } else {
                                    cell("—")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.screenPadding)
            }
        }
    }

    private func cell(_ text: String, width: CGFloat = 36,
                      header: Bool = false,
                      background: Color = .clear,
                      foreground: Color? = nil) -> some View {
        Text(text)
            .font(header ? DSFont.labelMD : DSFont.labelLG)
            .monospacedDigit()
            .lineLimit(1)
            .frame(width: width, height: 32)
            .background(background)
            .foregroundStyle(foreground ?? (header ? DSColor.onSurfaceVariant : DSColor.onSurface))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func scorePill(delta: Int) -> some View {
        Text("\(delta >= 0 ? "+" : "")\(delta) (\(Score.label(delta)))")
            .font(DSFont.labelMD)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(delta == 0 ? Color.clear : Color(hex: Score.color(delta)))
            .foregroundStyle(delta == 0 ? DSColor.onSurface : Color(hex: Score.onColor(delta)))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(delta == 0 ? DSColor.outlineVariant : .clear))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(DSFont.titleLG)
            .foregroundStyle(DSColor.onSurface)
    }
}
