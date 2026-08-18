import SwiftUI

struct ProfileView: View {
    @Environment(SessionViewModel.self) private var session
    @State private var model = ProfileViewModel()

    private var currentUserId: String? { AuthService.currentUserId }
    private var bag: [BagClub] { session.profile?.resolvedBag ?? Clubs.defaultBag }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if model.loadError { errorBanner }
                userCard
                statsCard
                if let stats = statsIfPlayed, stats.totalHolesPlayed > 0 {
                    distributionCard(stats)
                }
                handicapCard
                favoriteClubsCard
                bagLink
                DSButton(title: "Выйти из аккаунта", style: .secondary) {
                    session.signOut()
                }
            }
            .padding(DS.screenPadding)
        }
        .background(DSColor.surface)
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let uid = currentUserId { await model.load(userId: uid) }
        }
        .refreshable {
            if let uid = currentUserId { await model.load(userId: uid) }
        }
    }

    private var statsIfPlayed: PlayerStats? {
        guard let uid = currentUserId else { return nil }
        return Scoring.playerStats(rounds: model.rounds, userId: uid)
    }

    private var errorBanner: some View {
        HStack(spacing: 12) {
            Text("Не удалось загрузить статистику")
                .font(DSFont.labelLG)
                .foregroundStyle(DSColor.onSurface)
            Spacer()
            Button("Повторить") {
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
                Text(session.profile?.name ?? "Голфер")
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

    private var statsCard: some View {
        card(title: "Статистика") {
            if let stats = statsIfPlayed, stats.roundsPlayed > 0 {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    statCell("РАУНДОВ", "\(stats.roundsPlayed)")
                    statCell("СР. УДАРЫ", stats.avgShots.truncatingRemainder(dividingBy: 1) == 0
                             ? String(format: "%.0f", stats.avgShots)
                             : String(format: "%.1f", stats.avgShots))
                    statCell("ЛУЧШИЙ СЧЁТ", stats.bestScore.map(String.init) ?? "—")
                    statCell("BEST VS PAR", stats.bestScoreDiff.map { $0 > 0 ? "+\($0)" : "\($0)" } ?? "—")
                }
            } else {
                Text("Сыграйте первый раунд, чтобы увидеть статистику.")
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
            ("Хуже", stats.holeStats.worse, Score.color(3)),
        ]
        let total = stats.totalHolesPlayed
        func pct(_ n: Int) -> Int { total > 0 ? Int((Double(n) / Double(total) * 100).rounded()) : 0 }
        return card(title: "Распределение по лункам") {
            Text("За все \(total) \(pluralRu(total, "сыгранную лунку", "сыгранных лунки", "сыгранных лунок"))")
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
        card(title: "Гандикап") {
            if let uid = currentUserId,
               let handicap = Scoring.handicap(rounds: model.rounds, userId: uid) {
                Text(handicap.index >= 0
                     ? String(format: "%.1f", handicap.index)
                     : String(format: "+%.1f", abs(handicap.index)))
                    .font(DSFont.displayLG)
                    .foregroundStyle(DSColor.primary)
                    .monospacedDigit()
                Text(handicap.bestUsed == 8
                     ? "по лучшим 8 из \(handicap.basedOnRounds) раундов · WHS-метод (без course rating / slope)"
                     : "по \(handicap.basedOnRounds) \(pluralRu(handicap.basedOnRounds, "раунду", "раундам", "раундам")), среднее × 0.96")
                    .font(DSFont.labelMD)
                    .foregroundStyle(DSColor.onSurfaceVariant)
            } else {
                Text("Сыграйте минимум 3 раунда — рассчитаем по WHS (best 8 из последних 20 × 0.96).")
                    .font(DSFont.labelLG)
                    .foregroundStyle(DSColor.onSurfaceVariant)
            }
        }
    }

    private var favoriteClubsCard: some View {
        card(title: "Любимые клюшки") {
            if let uid = currentUserId {
                let stats = Array(Scoring.clubUsage(rounds: model.rounds, userId: uid).prefix(5))
                if stats.isEmpty {
                    Text("Статистика появится после первых ударов.")
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
                                    Text("\(stat.count) \(pluralRu(stat.count, "удар", "удара", "ударов")) · \(stat.percent)%")
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
                    Text("МОЯ СУМКА")
                        .font(DSFont.labelLG)
                        .tracking(2.5)
                        .foregroundStyle(DSColor.onPrimary)
                }
                HStack {
                    Text("\(bag.filter(\.enabled).count) клюшек · \(session.profile?.units == .yd ? "ярды" : "метры")")
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
