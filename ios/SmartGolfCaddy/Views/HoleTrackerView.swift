// ios/SmartGolfCaddy/Views/HoleTrackerView.swift
import SwiftUI
import UIKit

struct HoleTrackerView: View {
    let roundId: String
    let holeNumber: Int

    @Environment(SessionViewModel.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(AppStore.self) private var store
    @Environment(LocaleManager.self) private var lm
    @State private var model: HoleTrackerViewModel
    @State private var selectedClub: String = "Driver"
    @State private var showFinishConfirm = false
    @State private var showHoleEditor = false
    @State private var savingHole = false
    @State private var showHostOnlyHint = false

    private let haptics = UIImpactFeedbackGenerator(style: .medium)

    init(roundId: String, holeNumber: Int) {
        self.roundId = roundId
        self.holeNumber = holeNumber
        _model = State(initialValue: HoleTrackerViewModel(
            roundId: roundId,
            holeIndex: holeNumber - 1,
            userId: AuthService.currentUserId ?? ""
        ))
    }

    private var pickerClubs: [BagClub] {
        let enabled = (session.profile?.resolvedBag ?? Clubs.defaultBag).filter(\.enabled)
        return enabled.isEmpty ? Clubs.defaultBag : enabled
    }

    private var fullBag: [BagClub] { session.profile?.resolvedBag ?? Clubs.defaultBag }

    var body: some View {
        Group {
            if let round = model.round, let hole = model.hole {
                content(round: round, hole: hole)
            } else if let loadError = model.loadError {
                VStack(spacing: 16) {
                    Text(loadError)
                        .font(DSFont.bodyMD)
                        .foregroundStyle(DSColor.error)
                        .multilineTextAlignment(.center)
                    DSButton(title: lm.t.common.goHome, style: .secondary) { router.popToRoot() }
                        .padding(.horizontal, 48)
                }
                .padding(DS.screenPadding)
            } else {
                ProgressView(lm.t.common.loading)
            }
        }
        .background(DSColor.surface)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Group {
                    // «Лунка N / 0» при загрузке иначе — round ещё не пришёл.
                    if let round = model.round {
                        Text(lm.t.holeTracker.holeTitle(holeNumber, round.totalHoles))
                    } else {
                        Text(lm.t.holeTracker.holeTitleNoTotal(holeNumber))
                    }
                }
                .font(DSFont.titleLG)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    router.goHome()
                } label: {
                    Image(systemName: "house")
                }
                .accessibilityLabel(lm.t.common.goHome)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let round = model.round, round.playerIds.count > 1 {
                    Button {
                        router.push(.leaderboard(roundId: roundId))
                    } label: {
                        Image(systemName: "trophy")
                    }
                    .accessibilityLabel(lm.t.holeTracker.leaderboardAria)
                }
            }
        }
        .task {
            selectedClub = store.lastClubUsed
            let ids = pickerClubs.map(\.id)
            if !ids.contains(selectedClub) && selectedClub != Clubs.penaltyId { selectedClub = ids.first ?? "Driver" }
            model.updateWatchContext(clubs: ids, units: session.profile?.units ?? .m)
            model.start()
        }
        .onChange(of: session.profile) { _, profile in
            // Профиль (сумка/единицы) мог ещё не загрузиться к моменту
            // .task выше — как только он приходит, пересылаем часам
            // актуальный контекст (иначе часы застряли бы на дефолтной
            // сумке до следующего изменения раунда).
            model.updateWatchContext(clubs: pickerClubs.map(\.id), units: profile?.units ?? .m)
        }
        .onChange(of: model.round?.status) { _, status in
            // Заменяем только когда трекер наверху: если поверх открыта
            // таблица, она сама уйдёт по своей навигации, а двойная замена
            // ломает стек.
            guard status == .finished,
                  router.path.last == .hole(roundId: roundId, number: holeNumber) else { return }
            router.replaceLast(.results(roundId: roundId))
        }
        .confirmationDialog(lm.t.holeTracker.finishConfirmTitle, isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button(lm.t.holeTracker.finish, role: .destructive) {
                Task {
                    if await model.finish() {
                        router.replaceLast(.results(roundId: roundId))
                    }
                }
            }
            Button(lm.t.holeTracker.continueEditing, role: .cancel) {}
        } message: {
            Text(finishConfirmBody)
        }
        .sheet(isPresented: $showHoleEditor) {
            if let hole = model.hole {
                HoleEditorSheet(
                    holeNumber: holeNumber,
                    currentPar: hole.par,
                    currentDistance: hole.distanceMeters,
                    saving: savingHole,
                    onSave: { par, dist in
                        Task {
                            savingHole = true
                            let ok = await model.saveHoleConfig(par: par, distanceMeters: dist)
                            savingHole = false
                            if ok { showHoleEditor = false }
                        }
                    },
                    onCancel: { if !savingHole { showHoleEditor = false } }
                )
                .interactiveDismissDisabled(savingHole)
            }
        }
    }

    private var finishConfirmBody: String {
        guard let round = model.round else { return "" }
        if holeNumber < round.totalHoles {
            return lm.t.holeTracker.finishConfirmPartial(holeNumber - 1, round.totalHoles)
        }
        return lm.t.holeTracker.finishConfirmComplete
    }

    @ViewBuilder
    private func content(round: Round, hole: HoleConfig) -> some View {
        VStack(spacing: 0) {
            holeHeader(round: round, hole: hole)
            greenRow
            if round.playerIds.count > 1 { playerStrip(round: round, hole: hole) }
            ScrollView {
                VStack(spacing: 24) {
                    counter
                    if model.greenDistanceMeters == nil && model.canMarkGreen {
                        Text(lm.t.holeTracker.markGreenHint)
                            .font(DSFont.labelMD)
                            .foregroundStyle(DSColor.onSurfaceVariant)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DS.screenPadding)
                    }
                    if !model.currentClubs.isEmpty { series }
                    if let saveError = model.saveError {
                        Text(saveError)
                            .font(DSFont.labelLG)
                            .foregroundStyle(DSColor.error)
                    }
                    if model.hasQueuedShots {
                        Label(lm.t.holeTracker.offlineNotice, systemImage: "wifi.slash")
                            .font(DSFont.labelMD)
                            .foregroundStyle(DSColor.onSurfaceVariant)
                    }
                    clubPicker
                }
                .padding(.vertical, 16)
            }
            navigationButtons(round: round)
        }
    }

    private func holeHeader(round: Round, hole: HoleConfig) -> some View {
        HStack {
            Button {
                if model.isHost { showHoleEditor = true }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lm.t.common.par)
                        .font(DSFont.labelLG)
                        .foregroundStyle(DSColor.onPrimary.opacity(0.7))
                    Text("\(hole.par)")
                        .font(DSFont.headlineMD)
                        .foregroundStyle(DSColor.onPrimary)
                        .underline(model.isHost, pattern: .dot)
                }
            }
            .disabled(!model.isHost)
            .accessibilityLabel(lm.t.holeTracker.editParAria(hole.par))
            Spacer()
            Text("\(holeNumber)")
                .font(DSFont.displayLG)
                .foregroundStyle(DSColor.onPrimary)
            Spacer()
            Button {
                if model.isHost { showHoleEditor = true }
            } label: {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(lm.t.holeTracker.distanceShort)
                        .font(DSFont.labelLG)
                        .foregroundStyle(DSColor.onPrimary.opacity(0.7))
                    HStack(spacing: 6) {
                        Text("\(hole.distanceMeters) \(lm.t.common.metersShort)")
                            .font(DSFont.headlineMD)
                            .foregroundStyle(DSColor.onPrimary)
                            .underline(model.isHost, pattern: .dot)
                        Circle()
                            .fill(Color(hex: round.tee.bgHex))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(DSColor.onPrimary.opacity(0.3)))
                            .accessibilityLabel(lm.t.holeTracker.teeAria(round.tee.label))
                    }
                }
            }
            .disabled(!model.isHost)
            .accessibilityLabel(lm.t.holeTracker.editDistanceAria(hole.distanceMeters))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(DSColor.primaryContainer)
    }

    // Компактная строка «До грина» + кнопка отметки (3b-T3): под шапкой
    // пар/дист./тии, тот же primaryContainer-фон — визуально продолжение
    // шапки. Единицы — из профиля, как в RoundResultsView.avgDistanceText.
    @ViewBuilder
    private var greenRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 14))
                .foregroundStyle(DSColor.onPrimary.opacity(0.8))
            if !model.courseIdentified {
                // Ручной раунд без названия поля — метки гринов не собираются
                // (Greens.courseKey вернул nil), кнопку отметки не показываем.
                Text(lm.t.holeTracker.courseNotIdentified)
                    .font(DSFont.labelMD)
                    .foregroundStyle(DSColor.onPrimary.opacity(0.7))
            } else if let meters = model.greenDistanceMeters {
                Text(lm.t.holeTracker.toGreen(session.profile?.units == .yd
                     ? "\(Score.metersToYards(meters)) \(lm.t.common.yardsShort)"
                     : "\(meters) \(lm.t.common.metersShort)"))
                    .font(DSFont.labelLG)
                    .foregroundStyle(DSColor.onPrimary)
                    .monospacedDigit()
            } else {
                Text(lm.t.holeTracker.greenNotMarked)
                    .font(DSFont.labelMD)
                    .foregroundStyle(DSColor.onPrimary.opacity(0.7))
            }
            Spacer()
            if model.courseIdentified {
                Button {
                    Task { _ = await model.markGreen() }
                } label: {
                    Text(lm.t.holeTracker.onGreenButton)
                        .font(DSFont.labelMD)
                        .tracking(1.2)
                        .padding(.horizontal, 12)
                        .frame(minHeight: DS.touchTarget)
                }
                .foregroundStyle(DSColor.onPrimary)
                .background(DSColor.onPrimary.opacity(model.canMarkGreen ? 0.18 : 0.08))
                .clipShape(Capsule())
                .disabled(!model.canMarkGreen)
                .accessibilityLabel(lm.t.holeTracker.markGreenAria)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .background(DSColor.primaryContainer)
    }

    // Порт ленты игроков (HoleTracker.tsx:279-315): аватар-инициал, имя
    // («Вы» для себя), счётчик ударов лунки, выделение активного. Тап
    // доступен всем на свой слот; чужой слот — только хосту (сервер
    // enforce'ит host-or-self, здесь дублируем гейт для UI-подсказки).
    private func playerStrip(round: Round, hole: HoleConfig) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lm.t.holeTracker.playerSwitch)
                .font(DSFont.labelMD)
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(DSColor.onSurfaceVariant)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(round.playerIds, id: \.self) { uid in
                        playerChip(uid: uid, round: round, hole: hole)
                    }
                }
            }
            if showHostOnlyHint {
                Text(lm.t.holeTracker.hostScoresOthers)
                    .font(DSFont.labelMD)
                    .foregroundStyle(DSColor.onSurfaceVariant)
            }
        }
        .padding(.horizontal, DS.screenPadding)
        .padding(.top, 12)
    }

    private func playerChip(uid: String, round: Round, hole: HoleConfig) -> some View {
        let active = uid == model.activeUserId
        let isMe = uid == model.userId
        let name = round.players[uid]?.displayName ?? "—"
        let count = hole.shots[uid]?.count ?? 0
        return Button {
            selectPlayer(uid)
        } label: {
            HStack(spacing: 8) {
                Text(initials(name))
                    .font(DSFont.labelMD)
                    .foregroundStyle(active ? DSColor.primary : DSColor.onPrimary)
                    .frame(width: 24, height: 24)
                    .background(active ? DSColor.onPrimary : DSColor.primaryContainer)
                    .clipShape(Circle())
                Text(isMe ? lm.t.common.you : name)
                    .font(DSFont.labelLG)
                    .lineLimit(1)
                    .frame(maxWidth: 100, alignment: .leading)
                Text("\(count)")
                    .font(DSFont.labelLG.weight(.bold))
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .frame(minHeight: DS.touchTarget)
        }
        .foregroundStyle(active ? DSColor.onPrimary : DSColor.onSurface)
        .background(active ? DSColor.primary : DSColor.surfaceContainerLowest)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(active ? Color.clear : DSColor.outlineVariant.opacity(0.6)))
    }

    private func selectPlayer(_ uid: String) {
        guard model.canScoreForOthers || uid == model.userId else {
            showHostOnlyHint = true
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                showHostOnlyHint = false
            }
            return
        }
        model.setActiveUser(uid)
    }

    private func initials(_ name: String) -> String {
        let parts = name.trimmingCharacters(in: .whitespaces).split(separator: " ")
        if parts.isEmpty { return "—" }
        if parts.count == 1 { return String(parts[0].prefix(2)).uppercased() }
        let first = parts[0].first.map(String.init) ?? ""
        let last = parts[parts.count - 1].first.map(String.init) ?? ""
        return (first + last).uppercased()
    }

    // «Ваши удары» соло/для себя, «Удары: <имя>» когда хост ведёт счёт
    // за другого игрока (порт заголовка серии из HoleTracker.tsx:317-322).
    private var seriesTitle: String {
        guard let round = model.round, round.playerIds.count > 1,
              model.activeUserId != model.userId else {
            return lm.t.holeTracker.yourShots
        }
        return lm.t.holeTracker.shotsOf(round.players[model.activeUserId]?.displayName ?? "—")
    }

    private var counter: some View {
        VStack(spacing: 12) {
            Text(seriesTitle)
                .font(DSFont.labelLG)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(DSColor.onSurfaceVariant)
            HStack(spacing: 40) {
                Button {
                    haptics.impactOccurred()
                    let clubs = model.currentClubs
                    guard !clubs.isEmpty else { return }
                    let newClubs = Array(clubs.dropLast())
                    // Захватываем слот СИНХРОННО, до await: save() делает
                    // сетевой вызов, и если за это время хост переключит
                    // активного игрока, model.measuresDistances после await
                    // отразила бы уже нового игрока, а не того, за кого
                    // реально писался этот удар.
                    let ownSlot = model.measuresDistances
                    Task {
                        if await model.save(newClubs), let last = newClubs.last, ownSlot {
                            // Порт HoleTracker.tsx save(): «последняя клюшка»
                            // персонализируется только для своих ударов —
                            // иначе выбор хоста для товарища перезаписал бы
                            // дефолт клюшки самого хоста.
                            store.lastClubUsed = last
                        }
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 28, weight: .bold))
                        .frame(width: 64, height: 64)
                }
                .background(.clear)
                .foregroundStyle(DSColor.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DSColor.primary, lineWidth: 2))
                .disabled(model.currentClubs.isEmpty || model.saving)
                .opacity(model.currentClubs.isEmpty || model.saving ? 0.3 : 1)

                Text("\(model.currentClubs.count)")
                    .font(DSFont.bold(64))
                    .foregroundStyle(DSColor.primary)
                    .monospacedDigit()
                    .frame(minWidth: 80)

                Button {
                    haptics.impactOccurred()
                    let newClubs = model.currentClubs + [selectedClub]
                    // Захватываем слот СИНХРОННО, до await — см. комментарий
                    // у кнопки «минус» выше.
                    let ownSlot = model.measuresDistances
                    Task {
                        if await model.save(newClubs), let last = newClubs.last, ownSlot {
                            // Порт HoleTracker.tsx save(): «последняя клюшка»
                            // персонализируется только для своих ударов —
                            // иначе выбор хоста для товарища перезаписал бы
                            // дефолт клюшки самого хоста.
                            store.lastClubUsed = last
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .bold))
                        .frame(width: 64, height: 64)
                }
                .background(DSColor.primary)
                .foregroundStyle(DSColor.onPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .disabled(model.saving)
                .opacity(model.saving ? 0.3 : 1)
            }
            Text(lm.t.holeTracker.shotsUppercase)
                .font(DSFont.labelMD)
                .tracking(3)
                .foregroundStyle(DSColor.onSurfaceVariant)
        }
    }

    private var series: some View {
        VStack(spacing: 6) {
            Text(lm.t.holeTracker.shotSeries)
                .font(DSFont.labelMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
            FlowLayoutCompat(items: Array(model.currentClubs.enumerated()), spacing: 6) { index, club in
                Text(model.currentDistances.indices.contains(index) && model.currentDistances[index] > 0
                     ? "\(index + 1). \(Clubs.label(for: club, in: fullBag)) · \(model.currentDistances[index]) \(lm.t.common.metersShort)"
                     : "\(index + 1). \(Clubs.label(for: club, in: fullBag))")
                    .font(DSFont.labelMD)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(DSColor.surfaceContainer)
                    .foregroundStyle(DSColor.onSurfaceVariant)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, DS.screenPadding)
            Label(model.gpsReady ? lm.t.holeTracker.gpsReady : lm.t.holeTracker.gpsWaiting,
                  systemImage: model.gpsReady ? "location.fill" : "location.slash")
                .font(DSFont.labelMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
        }
    }

    private var clubPicker: some View {
        VStack(spacing: 8) {
            Text(lm.t.holeTracker.clubPickerUppercase)
                .font(DSFont.labelLG)
                .tracking(1.5)
                .foregroundStyle(DSColor.onSurfaceVariant)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pickerClubs) { club in
                        ClubChipView(
                            label: Clubs.label(for: club.id, in: fullBag),
                            selected: selectedClub == club.id
                        ) {
                            selectedClub = club.id
                        }
                    }
                    ClubChipView(
                        label: Clubs.penaltyId,
                        selected: selectedClub == Clubs.penaltyId
                    ) {
                        selectedClub = Clubs.penaltyId
                    }
                }
                .padding(.horizontal, DS.screenPadding)
            }
        }
        .onChange(of: pickerClubs.map(\.id)) { _, ids in
            if !ids.contains(selectedClub) && selectedClub != Clubs.penaltyId { selectedClub = ids.first ?? "Driver" }
        }
    }

    private func navigationButtons(round: Round) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                DSButton(title: lm.t.holeTracker.prev, icon: "chevron.left", style: .secondary,
                         disabled: holeNumber == 1) {
                    router.replaceLast(.hole(roundId: roundId, number: holeNumber - 1))
                }
                if holeNumber < round.totalHoles {
                    DSButton(title: lm.t.holeTracker.next, icon: "chevron.right") {
                        router.replaceLast(.hole(roundId: roundId, number: holeNumber + 1))
                    }
                } else {
                    // Тот же host-гейт, что у «досрочно»: не-хосту — та же
                    // кнопка текстом «Завершит хост» и disabled, как на вебе.
                    // В соло isHost всегда true — видимых изменений нет.
                    DSButton(title: model.isHost ? lm.t.holeTracker.finishGame : lm.t.holeTracker.finishWaitHost, icon: "flag.fill",
                             disabled: !model.isHost || model.finishing || model.saving) {
                        showFinishConfirm = true
                    }
                }
            }
            if model.isHost && holeNumber < round.totalHoles {
                DSButton(title: lm.t.holeTracker.finishEarly, icon: "flag", style: .secondary,
                         disabled: model.finishing) {
                    showFinishConfirm = true
                }
            }
        }
        .padding(.horizontal, DS.screenPadding)
        .padding(.bottom, 12)
    }
}
