import SwiftUI

// Публичные статические страницы сайта (App Store 5.1.1(v) — политика,
// условия и поддержка должны быть доступны из приложения). Один домен —
// правка адреса при переезде на свой домен делается в одном месте.
private enum LegalLinks {
    // T4: локализованные подписи читаются на каждый рендер (не кэшируются
    // статически), иначе смена языка не обновила бы список без перезапуска.
    static var all: [(label: String, url: URL)] {
        let t = AppLocaleStore.strings.profile
        return [
            (t.legalPrivacy, URL(string: "https://smart-golf-caddy.web.app/privacy")!),
            (t.legalTerms, URL(string: "https://smart-golf-caddy.web.app/terms")!),
            (t.legalSupport, URL(string: "https://smart-golf-caddy.web.app/support")!),
        ]
    }
}

struct ProfileView: View {
    @Environment(SessionViewModel.self) private var session
    @Environment(LocaleManager.self) private var lm
    @State private var model = ProfileViewModel()
    @State private var accountModel = AccountViewModel()

    private var currentUserId: String? { AuthService.currentUserId }
    private var bag: [BagClub] { session.profile?.resolvedBag ?? Clubs.defaultBag }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if model.loadError { errorBanner }
                userCard
                languageToggle
                statsCard
                if let stats = statsIfPlayed, stats.totalHolesPlayed > 0 {
                    distributionCard(stats)
                }
                handicapCard
                favoriteClubsCard
                bagLink
                legalLinks
                DSButton(title: lm.t.profile.signOut, style: .secondary) {
                    session.signOut()
                }
                dangerZone
            }
            .padding(DS.screenPadding)
        }
        .background(DSColor.surface)
        .navigationTitle(lm.t.profile.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let uid = currentUserId { await model.load(userId: uid) }
        }
        .refreshable {
            if let uid = currentUserId { await model.load(userId: uid) }
        }
        .confirmationDialog(
            lm.t.profile.deleteAccountConfirmTitle, isPresented: $accountModel.showDeleteConfirm, titleVisibility: .visible
        ) {
            Button(lm.t.common.delete, role: .destructive) {
                Task {
                    if await accountModel.confirmDelete() {
                        session.signOut()
                    }
                }
            }
            Button(lm.t.common.cancel, role: .cancel) {}
        } message: {
            Text(lm.t.profile.deleteAccountConfirmBody)
        }
    }

    // Визуально отделена от остального профиля (App Store 5.1.1(v) — кнопка
    // удаления аккаунта должна легко находиться, не быть закопана).
    private var dangerZone: some View {
        VStack(spacing: 12) {
            Rectangle()
                .fill(DSColor.outlineVariant.opacity(0.3))
                .frame(height: 1)
            if let error = accountModel.deleteError {
                Text(error)
                    .font(DSFont.labelLG)
                    .foregroundStyle(DSColor.error)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            DSButton(
                title: lm.t.profile.deleteAccount, icon: "trash", style: .destructive,
                disabled: accountModel.deletingAccount
            ) {
                accountModel.deleteError = nil
                accountModel.showDeleteConfirm = true
            }
        }
        .padding(.top, 4)
    }

    // Юридические и справочные ссылки — намеренно отделены от кнопок
    // выхода/удаления аккаунта, чтобы по ним не промахивались рядом с
    // опасным действием. `Link` открывает системный браузер, не веб-вью в
    // приложении.
    private var legalLinks: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle()
                .fill(DSColor.outlineVariant.opacity(0.3))
                .frame(height: 1)
                .padding(.bottom, 8)
            ForEach(LegalLinks.all, id: \.url) { item in
                Link(destination: item.url) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 14))
                        Text(item.label)
                            .font(DSFont.labelLG)
                    }
                    .foregroundStyle(DSColor.onSurfaceVariant)
                    .frame(minHeight: DS.touchTarget, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var statsIfPlayed: PlayerStats? {
        guard let uid = currentUserId else { return nil }
        return Scoring.playerStats(rounds: model.rounds, userId: uid)
    }

    private var errorBanner: some View {
        HStack(spacing: 12) {
            Text(lm.t.profile.loadError)
                .font(DSFont.labelLG)
                .foregroundStyle(DSColor.onSurface)
            Spacer()
            Button(lm.t.common.retry) {
                Task {
                    if let uid = currentUserId { await model.load(userId: uid) }
                }
            }
            .font(DSFont.labelLG)
            .foregroundStyle(DSColor.primary)
            .frame(minHeight: DS.touchTarget)
        }
        .padding(.horizontal, 14)
        .background(DSColor.errorContainer.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
    }

    private var userCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(DSColor.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.profile?.name ?? lm.t.common.fallbackName)
                    .font(DSFont.titleLG)
                    .foregroundStyle(DSColor.onSurface)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(16)
        .background(DSColor.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: DS.cornerRadius).stroke(DSColor.outlineVariant.opacity(0.25)))
    }

    // T4: переключатель языка — тот же визуальный приём пилюли, что у
    // unitsToggle в MyBagView. Подписи языков — на самих языках («Русский»/
    // «English»), не переводятся: игрок, случайно попавший в чужой язык,
    // должен узнать свой в любом состоянии интерфейса.
    private var languageToggle: some View {
        VStack(spacing: 6) {
            Text(lm.t.profile.language)
                .font(DSFont.labelMD)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(DSColor.onSurfaceVariant)
            HStack(spacing: 0) {
                ForEach([AppLocale.ru, AppLocale.en], id: \.self) { locale in
                    Button {
                        changeLanguage(locale)
                    } label: {
                        Text(locale == .ru ? "Русский" : "English")
                            .font(DSFont.labelLG)
                            .frame(maxWidth: .infinity, minHeight: DS.touchTarget)
                    }
                    .background(lm.current == locale ? DSColor.surfaceContainerLowest : .clear)
                    .foregroundStyle(lm.current == locale ? DSColor.primary : DSColor.onSurfaceVariant)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(4)
            .background(DSColor.surfaceContainer)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // Применяется немедленно (каждый читатель environment(LocaleManager.self)
    // перерисовывается на месте — без перезапуска), запись в Firestore —
    // отдельно и некритично (тот же паттерн, что changeUnits в MyBagView):
    // UI уже отражает выбор, повторной попытки при сетевой ошибке не нужно.
    private func changeLanguage(_ locale: AppLocale) {
        guard locale != lm.current else { return }
        lm.set(locale)
        guard let uid = currentUserId else { return }
        Task { try? await UsersService.updateLocale(uid: uid, locale: locale) }
    }

    private var statsCard: some View {
        card(title: lm.t.profile.statsTitle) {
            if let stats = statsIfPlayed, stats.roundsPlayed > 0 {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    statCell(lm.t.profile.roundsLabel, "\(stats.roundsPlayed)")
                    statCell(lm.t.profile.avgShotsLabel, stats.avgShots.truncatingRemainder(dividingBy: 1) == 0
                             ? String(format: "%.0f", stats.avgShots)
                             : String(format: "%.1f", stats.avgShots))
                    statCell(lm.t.profile.bestScoreLabel, stats.bestScore.map(String.init) ?? "—")
                    statCell(lm.t.profile.bestVsParLabel, stats.bestScoreDiff.map { $0 > 0 ? "+\($0)" : "\($0)" } ?? "—")
                }
            } else {
                Text(lm.t.profile.noStatsYet)
                    .font(DSFont.labelLG)
                    .foregroundStyle(DSColor.onSurfaceVariant)
            }
        }
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(DSFont.labelMD)
                .tracking(1.2)
                .foregroundStyle(DSColor.onSurfaceVariant)
            Text(value)
                .font(DSFont.headlineMD)
                .foregroundStyle(DSColor.primary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func distributionCard(_ stats: PlayerStats) -> some View {
        let items: [(label: String, count: Int, hex: String)] = [
            ("Eagle+", stats.holeStats.eagle, Score.color(-2)),
            ("Birdie", stats.holeStats.birdie, Score.color(-1)),
            ("Par", stats.holeStats.par, Score.color(0)),
            ("Bogey", stats.holeStats.bogey, Score.color(1)),
            ("Double", stats.holeStats.double, Score.color(2)),
            (lm.t.profile.worseLabel, stats.holeStats.worse, Score.color(3)),
        ]
        let total = stats.totalHolesPlayed
        func pct(_ n: Int) -> Int { total > 0 ? Int((Double(n) / Double(total) * 100).rounded()) : 0 }
        return card(title: lm.t.profile.distributionTitle) {
            Text(lm.t.profile.overAllHoles(total, plural(total, lm.current, lm.t.profile.playedHolesWord)))
                .font(DSFont.labelMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(items.filter { $0.count > 0 }, id: \.label) { item in
                        Rectangle()
                            .fill(Color(hex: item.hex))
                            .frame(width: geo.size.width * CGFloat(item.count) / CGFloat(max(total, 1)))
                    }
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())
            .background(Capsule().fill(DSColor.surfaceContainer))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(items, id: \.label) { item in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: item.hex))
                            .frame(width: 12, height: 12)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(DSColor.outlineVariant.opacity(0.3)))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.label)
                                .font(DSFont.labelMD)
                                .foregroundStyle(DSColor.onSurface)
                                .lineLimit(1)
                            Text("\(item.count) · \(pct(item.count))%")
                                .font(DSFont.labelMD)
                                .foregroundStyle(DSColor.onSurfaceVariant)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var handicapCard: some View {
        card(title: lm.t.profile.handicapTitle) {
            if let uid = currentUserId,
               let handicap = Scoring.handicap(rounds: model.rounds, userId: uid) {
                Text(handicap.index >= 0
                     ? String(format: "%.1f", handicap.index)
                     : String(format: "+%.1f", abs(handicap.index)))
                    .font(DSFont.displayLG)
                    .foregroundStyle(DSColor.primary)
                    .monospacedDigit()
                Text(handicap.bestUsed == 8
                     ? lm.t.profile.handicapBest8(handicap.basedOnRounds)
                     : lm.t.profile.handicapAvg(handicap.basedOnRounds, plural(handicap.basedOnRounds, lm.current, lm.t.profile.roundsWord)))
                    .font(DSFont.labelMD)
                    .foregroundStyle(DSColor.onSurfaceVariant)
            } else {
                Text(lm.t.profile.handicapEmpty)
                    .font(DSFont.labelLG)
                    .foregroundStyle(DSColor.onSurfaceVariant)
            }
        }
    }

    private var favoriteClubsCard: some View {
        card(title: lm.t.profile.favoriteClubsTitle) {
            if let uid = currentUserId {
                let stats = Array(Scoring.clubUsage(rounds: model.rounds, userId: uid).prefix(5))
                if stats.isEmpty {
                    Text(lm.t.profile.favoriteClubsEmpty)
                        .font(DSFont.labelLG)
                        .foregroundStyle(DSColor.onSurfaceVariant)
                } else {
                    let maxCount = stats.first?.count ?? 1
                    VStack(spacing: 10) {
                        ForEach(stats) { stat in
                            VStack(spacing: 4) {
                                HStack {
                                    Text(Clubs.label(for: stat.club, in: bag))
                                        .font(DSFont.bodyMD)
                                        .foregroundStyle(DSColor.onSurface)
                                    Spacer()
                                    Text("\(stat.count) \(plural(stat.count, lm.current, lm.t.profile.shotsWord)) · \(stat.percent)%")
                                        .font(DSFont.labelMD)
                                        .foregroundStyle(DSColor.onSurfaceVariant)
                                }
                                GeometryReader { geo in
                                    Capsule()
                                        .fill(DSColor.primary)
                                        .frame(width: geo.size.width * CGFloat(stat.count) / CGFloat(max(maxCount, 1)))
                                }
                                .frame(height: 8)
                                .background(Capsule().fill(DSColor.surfaceContainer))
                            }
                        }
                    }
                }
            }
        }
    }

    private var bagLink: some View {
        NavigationLink(value: Route.myBag) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "briefcase")
                        .font(.system(size: 20))
                        .foregroundStyle(DSColor.onPrimary)
                        .frame(width: 44, height: 44)
                        .background(DSColor.onPrimary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text(lm.t.profile.myBagLink)
                        .font(DSFont.labelLG)
                        .tracking(2.5)
                        .foregroundStyle(DSColor.onPrimary)
                }
                HStack {
                    Text(lm.t.profile.clubsCountAndUnit(
                        bag.filter(\.enabled).count,
                        plural(bag.filter(\.enabled).count, lm.current, lm.t.common.clubsWord),
                        session.profile?.units == .yd ? lm.t.myBag.yardsWord : lm.t.myBag.metersWord
                    ))
                        .font(DSFont.bodyMD)
                        .foregroundStyle(DSColor.onPrimary.opacity(0.85))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(DSColor.onPrimary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [DSColor.primaryContainer, DSColor.primary],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
        }
        .buttonStyle(.plain)
    }

    private func card(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(DSFont.titleLG)
                .foregroundStyle(DSColor.onSurface)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: DS.cornerRadius).stroke(DSColor.outlineVariant.opacity(0.25)))
    }
}
