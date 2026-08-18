import SwiftUI

struct HomeView: View {
    @Environment(SessionViewModel.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(AppStore.self) private var store
    @State private var model = HomeViewModel()

    private var firstName: String {
        let name = session.profile?.name ?? "Голфер"
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    private var currentUserId: String? { AuthService.currentUserId }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let message = session.errorMessage {
                    profileErrorBanner(message)
                        .padding(.horizontal, DS.screenPadding)
                        .padding(.top, 24)
                }
                if let active = model.activeRound {
                    resumeCard(active)
                        .padding(.horizontal, DS.screenPadding)
                        .padding(.top, 24)
                }
                VStack(spacing: 12) {
                    DSButton(title: "Начать новый раунд", icon: "plus") {
                        router.push(.courseSearch)
                    }
                    DSButton(title: "Быстрый старт без выбора поля", icon: "bolt", style: .secondary) {
                        store.prefillCourseName = nil
                        store.selectedCourse = nil
                        router.push(.roundSetup)
                    }
                }
                .padding(.horizontal, DS.screenPadding)
                .padding(.top, 24)

                if model.loadError {
                    errorBanner
                        .padding(.horizontal, DS.screenPadding)
                        .padding(.top, 24)
                }

                if !model.recentFinished.isEmpty {
                    recentSection
                        .padding(.horizontal, DS.screenPadding)
                        .padding(.top, 32)
                }
            }
            .padding(.bottom, 32)
        }
        .background(DSColor.surface)
        .task {
            if let uid = currentUserId {
                await model.load(userId: uid)
            }
        }
        .refreshable {
            if let uid = currentUserId {
                await model.load(userId: uid)
            }
        }
        .onChange(of: router.path) { _, path in
            // Возврат в корень стека (финиш/выход из раунда) → обновить список.
            if path.isEmpty, let uid = currentUserId {
                Task { await model.load(userId: uid) }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ДОБРО ПОЖАЛОВАТЬ")
                        .font(DSFont.labelLG)
                        .tracking(2.5)
                        .foregroundStyle(DSColor.onPrimary.opacity(0.7))
                    Text(firstName)
                        .font(DSFont.headlineLG)
                        .foregroundStyle(DSColor.onPrimary)
                }
                Spacer()
                Button {
                    session.signOut()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 18))
                        .foregroundStyle(DSColor.onPrimary.opacity(0.8))
                        .frame(minWidth: DS.touchTarget, minHeight: DS.touchTarget)
                }
                .accessibilityLabel("Выйти")
            }
        }
        .padding(.horizontal, DS.screenPadding)
        .padding(.top, 40)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [DSColor.primaryContainer, DSColor.primary],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private func resumeCard(_ round: Round) -> some View {
        Button {
            guard let uid = currentUserId else { return }
            router.push(.hole(roundId: round.id,
                              number: HomeViewModel.resumeHoleNumber(round: round, userId: uid)))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .foregroundStyle(DSColor.onPrimary)
                    .frame(width: 40, height: 40)
                    .background(DSColor.primary)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("ПРОДОЛЖИТЬ РАУНД")
                        .font(DSFont.labelMD)
                        .tracking(1.2)
                        .foregroundStyle(DSColor.primary)
                    Text(round.courseName)
                        .font(DSFont.bodyMD)
                        .foregroundStyle(DSColor.onSurface)
                        .lineLimit(1)
                    if let uid = currentUserId {
                        Text(HomeViewModel.resumeSubtitle(round: round, userId: uid))
                            .font(DSFont.labelMD)
                            .foregroundStyle(DSColor.onSurfaceVariant)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(DSColor.primary)
            }
            .padding(16)
            .background(DSColor.primaryContainer.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DS.cornerRadius)
                    .stroke(DSColor.primary.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
    }

    /// Ошибка подписки на профиль (напр. потеря сети сразу после входа) —
    /// без кнопки: session сам обновится, как только подписка восстановится.
    private func profileErrorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Text(message)
                .font(DSFont.labelLG)
                .foregroundStyle(DSColor.onSurface)
            Spacer()
        }
        .padding(14)
        .background(DSColor.errorContainer.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
    }

    private var errorBanner: some View {
        HStack(spacing: 12) {
            Text("Не удалось загрузить раунды")
                .font(DSFont.labelLG)
                .foregroundStyle(DSColor.onSurface)
            Spacer()
            Button("Повторить") {
                Task {
                    if let uid = currentUserId {
                        await model.load(userId: uid)
                    }
                }
            }
            .font(DSFont.labelLG)
            .foregroundStyle(DSColor.primary)
            .frame(minHeight: DS.touchTarget)
        }
        .padding(14)
        .background(DSColor.errorContainer.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Последние раунды")
                .font(DSFont.titleLG)
                .foregroundStyle(DSColor.onSurface)
            ForEach(model.recentFinished) { round in
                Button {
                    router.push(.results(roundId: round.id))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(round.courseName)
                                .font(DSFont.bodyMD)
                                .foregroundStyle(DSColor.onSurface)
                                .lineLimit(1)
                            Text(subtitle(for: round))
                                .font(DSFont.labelMD)
                                .foregroundStyle(DSColor.onSurfaceVariant)
                        }
                        Spacer()
                        if let uid = currentUserId {
                            Text(scoreSummary(round, uid: uid))
                                .font(DSFont.titleLG)
                                .foregroundStyle(DSColor.primary)
                                .monospacedDigit()
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
                .buttonStyle(.plain)
            }
        }
    }

    private func subtitle(for round: Round) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM yyyy"
        let date = formatter.string(from: round.createdAt)
        return "\(date) · \(round.totalHoles) \(pluralRu(round.totalHoles, "лунка", "лунки", "лунок"))"
    }

    private func scoreSummary(_ round: Round, uid: String) -> String {
        guard round.players[uid] != nil else { return "" }
        let totals = Scoring.playerTotals(round: round, userId: uid)
        let sign = totals.scoreDiff >= 0 ? "+" : ""
        return "\(totals.totalScore) (\(sign)\(totals.scoreDiff))"
    }
}
