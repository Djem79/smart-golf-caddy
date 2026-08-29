// ios/SmartGolfCaddyWatch/Views/WatchHoleView.swift
// Экран лунки на часах — счёт ударов и выбранная клюшка ГЛАВНЫЕ элементы
// экрана (дословно от владельца: «нам не нужны три цифры, нам нужно
// просто до флажка, и всё. И главное — записывать удары и какие клюшки,
// потому что это наша фишка»). Дистанция до грина — вспомогательная
// строка сверху, не акцент. Номер лунки/пар — компактная строка над ней.
// ВСЁ помещается на 41мм и 46мм БЕЗ прокрутки — никакого ScrollView здесь
// быть не должно. Никакого WatchConnectivity — только VM.
import SwiftUI

struct WatchHoleView: View {
    let viewModel: WatchRoundViewModel

    // Владелец жизненного цикла GPS-трекинга: старт при появлении ЭТОГО
    // экрана (лунки), стоп при уходе — батарея часов дороже телефонной.
    // Держим как let-ссылку на .shared (как WatchRootView держит
    // PhoneBridge.shared) — @Observable сам заводит трекинг чтения без
    // property wrapper'а. import CoreLocation здесь НЕ нужен: публичный
    // тип сервиса — Foundation-only GeoFix (см. CLAUDE.md).
    private let locationService = WatchLocationService.shared

    // DEBUG-only: запуск с launch argument -watchPreviewShowPicker сразу
    // открывает пикер клюшек — нужно для скриншот-доказательства без
    // возможности скриптованного тапа по симулятору часов.
    @State private var showPicker: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-watchPreviewShowPicker")
        #else
        return false
        #endif
    }()

    private var totalHoles: Int { viewModel.snapshot?.totalHoles ?? 1 }

    /// T5 (watch localization): resolved from the active snapshot's locale
    /// (falls back to the watch's own system language before any snapshot
    /// arrives) — same shared Strings.ru/.en dictionary the phone reads,
    /// not a second mechanism. See WatchRoundViewModel.strings.
    private var t: Strings { viewModel.strings }

    private var unitsYards: Bool { viewModel.snapshot?.units == .yd }
    private var unitLabel: String { unitsYards ? t.common.yardsShort : t.common.metersShort }

    /// Числовое значение дистанции до грина — БЕЗ словесной подписи (Fix,
    /// живое ревью task 6, второй заход: «убрать словесную подпись у
    /// дистанции совсем и увеличить сами цифры» — слова «до грина»/«to
    /// green» съедали строку и жались к краям на 41мм). На экране остаётся
    /// только число + флажок (SF Symbol, общепринятое обозначение на
    /// гольф-часах) + мелкая единица измерения. «—» вместо числа, когда
    /// метки грина для лунки нет ИЛИ GPS-фикс негоден (устарел/неточен/
    /// отсутствует — WatchRoundViewModel.greenDistanceMeters, единый
    /// nil-путь для обоих случаев). НИКОГДА не «0» и не устаревшее
    /// значение.
    private var greenDistanceValue: String {
        guard let meters = viewModel.greenDistanceMeters else { return "—" }
        let value = unitsYards ? Score.metersToYards(meters) : meters
        return "\(value)"
    }

    /// Полная фраза ТОЛЬКО для VoiceOver — на экране слов нет, но незрячему
    /// пользователю нужно услышать смысл числа, а не голый «сто сорок два»
    /// без единиц и назначения. Доступна и в состоянии «—»: `toGreen`
    /// повторно используется здесь (число+юнит), а не на экране — поэтому
    /// его НЕ следует удалять из словаря вместе с визуальной строкой.
    private var greenDistanceAria: String {
        guard viewModel.greenDistanceMeters != nil else { return t.watch.distanceUnavailableAria }
        return t.holeTracker.toGreen("\(greenDistanceValue) \(unitLabel)")
    }

    var body: some View {
        VStack(spacing: 3) {
            holeNavRow
            greenDistanceRow

            Divider().overlay(WatchColor.textSecondary.opacity(0.25))

            // Счёт — САМЫЙ крупный элемент экрана (Fix 1, живое ревью
            // task 6): «нам не нужны три цифры... главное — записывать
            // удары и какие клюшки». displayLG — самый большой токен
            // DSFont, тот же, что раньше носила дистанция.
            shotRow

            Divider().overlay(WatchColor.textSecondary.opacity(0.25))

            clubRow
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WatchColor.background)
        // Пустой (не nil) title — на watchOS ДАЖЕ пустой title резервирует
        // стандартную высоту-под-системные-часы у NavigationStack; без
        // этого модификатора контент рендерится full-bleed и стрелка
        // смены лунки наезжает на "8:58" в правом верхнем углу (Fix 3,
        // живое ревью task 6, дефект на 41mm-pending-ru.png). Само имя
        // курса всё равно не показывается — требование "убрать название
        // поля" по-прежнему выполнено, тут нет текста вообще.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                WatchClubPicker(
                    clubs: viewModel.clubs,
                    selectedClub: viewModel.selectedClub,
                    title: t.common.missingCustomClub,
                    onSelect: { club in
                        viewModel.selectedClub = club
                        showPicker = false
                    }
                )
            }
        }
        .onAppear {
            locationService.startTracking()
            viewModel.currentFix = locationService.lastFix
        }
        .onDisappear {
            locationService.stopTracking()
        }
        .onChange(of: locationService.lastFix) { _, newFix in
            viewModel.currentFix = newFix
        }
    }

    /// «‹ Лунка 3 › Пар 4» — одна компактная строка: номер лунки со
    /// стрелками навигации + пар. Никакой отдельной строки под неё и
    /// никакого названия поля (оба явно убраны по запросу владельца).
    private var holeAndParLabel: String {
        let holeTitle = t.holeTracker.holeTitleNoTotal(viewModel.holeNumber)
        guard let par = viewModel.currentHole?.par else { return holeTitle }
        return "\(holeTitle) · \(t.common.par) \(par)"
    }

    private var holeNavRow: some View {
        HStack(spacing: 2) {
            Button {
                viewModel.previousHole()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.holeNumber <= 1 ? WatchColor.textSecondary : WatchColor.accent)
            .disabled(viewModel.holeNumber <= 1)
            .frame(width: 28, height: 28)

            Spacer(minLength: 2)

            Text(holeAndParLabel)
                .font(DSFont.labelLG)
                .foregroundStyle(WatchColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 2)

            Button {
                viewModel.nextHole()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.holeNumber >= totalHoles ? WatchColor.textSecondary : WatchColor.accent)
            .disabled(viewModel.holeNumber >= totalHoles)
            .frame(width: 28, height: 28)
        }
    }

    /// Флажок (мелко) + крупное число + мелкая единица измерения — БЕЗ
    /// слов. Флажок сам по себе однозначно читается как «дистанция до
    /// грина» на гольф-часах (тот же язык, что у Garmin), поэтому текстовая
    /// подпись избыточна и убрана целиком (Fix, живое ревью task 6, второй
    /// заход). Единица измерения остаётся — без неё число неоднозначно
    /// (метры/ярды берутся из настроек пользователя).
    private var greenDistanceRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "flag.fill")
                .font(.system(size: 14))
                .foregroundStyle(WatchColor.textSecondary)
            Text(greenDistanceValue)
                .font(DSFont.headlineLG)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(WatchColor.textPrimary)
            Text(unitLabel)
                .font(DSFont.labelMD)
                .foregroundStyle(WatchColor.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(greenDistanceAria)
    }

    /// Счёт лунки МЕЖДУ кнопками ⊖/⊕ — самый крупный элемент экрана
    /// (Fix 1, живое ревью task 6). Подпись «ударов»/«shots» под числом
    /// не нужна (избыточна рядом с самими кнопками) — счёт озвучивается
    /// только через accessibilityLabel.
    private var shotRow: some View {
        HStack(spacing: 14) {
            Button {
                viewModel.removeShot()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: DS.touchTarget, height: DS.touchTarget)
                    .background(WatchColor.textSecondary.opacity(0.2), in: Circle())
                    .foregroundStyle(WatchColor.textPrimary)
            }
            .buttonStyle(.plain)
            // Кнопка "-" снимает ТОЛЬКО ещё не подтверждённый (локальный)
            // удар — серверный удар с часов не снять (см.
            // WatchRoundViewModel.removeShot()), поэтому дизейблим, когда
            // локального хвоста нет, а не когда счёт лунки равен нулю.
            .disabled(viewModel.pendingClubs.isEmpty)
            .accessibilityLabel(t.watch.removeShotAria)

            Text("\(viewModel.shotCount)")
                .font(DSFont.displayLG)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(minWidth: 46)
                .foregroundStyle(WatchColor.textPrimary)
                .accessibilityLabel(t.watch.shotsOnHoleAria(
                    viewModel.shotCount, plural(viewModel.shotCount, viewModel.locale, t.watch.shotsWord)
                ))

            Button {
                viewModel.addShot()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: DS.touchTarget, height: DS.touchTarget)
                    .background(DSColor.primary, in: Circle())
                    .foregroundStyle(DSColor.onPrimary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.clubs.isEmpty)
            .accessibilityLabel(t.watch.addShotAria)
        }
        .frame(maxWidth: .infinity)
    }

    /// Строка клюшки — второй по значимости элемент экрана (Fix 1, живое
    /// ревью task 6): «какими клюшками» — суть продукта, название должно
    /// быть видно и хорошо читаться, крупнее прежнего лейбла. Плейсхолдер
    /// (`common.missingCustomClub`) — ТОЛЬКО пока выбора вообще не было
    /// (`selectedClub == nil`); как только игрок выбрал клюшку (в пикере
    /// или как дефолт addShot() зафиксировал явным выбором), здесь стоит
    /// её реальное название. Несёт и индикатор синхронизации — компактная
    /// иконка ВНУТРИ строки (не отдельной строкой) экономит вертикальное
    /// место, при этом остаётся видимой, как требует владелец.
    private var clubRow: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "figure.golf")
                    .font(.system(size: 16))
                    .foregroundStyle(WatchColor.accent)
                Text(viewModel.selectedClub ?? t.common.missingCustomClub)
                    .font(DSFont.headlineMD)
                    .foregroundStyle(WatchColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                syncStatusDot
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(WatchColor.textSecondary)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: DS.touchTarget)
            .background(WatchColor.textSecondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(clubRowAccessibilityLabel)
    }

    @ViewBuilder
    private var syncStatusDot: some View {
        if viewModel.currentHoleSyncFailed {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(WatchColor.error)
        } else if viewModel.pendingCount > 0 {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 13))
                .foregroundStyle(WatchColor.pending)
        }
    }

    private var clubRowAccessibilityLabel: String {
        let clubLabel = viewModel.selectedClub ?? t.common.missingCustomClub
        if viewModel.currentHoleSyncFailed {
            return "\(clubLabel). \(t.watch.syncFailedAria)"
        }
        if viewModel.pendingCount > 0 {
            return "\(clubLabel). \(t.watch.notSynced(viewModel.pendingCount))"
        }
        return clubLabel
    }
}

#Preview {
    let snapshot = WatchRoundSnapshot(
        roundId: "preview",
        courseName: "Pebble Beach",
        totalHoles: 18,
        holes: [WatchHole(number: 3, par: 4, distanceMeters: 320, myShots: 1)],
        clubs: ["Driver", "7 Iron", "Putter"],
        greens: [:],
        activeHoleNumber: 3,
        units: .m,
        locale: .ru,
        updatedAt: Date()
    )
    return NavigationStack {
        WatchHoleView(viewModel: WatchRoundViewModel(snapshot: snapshot))
    }
}
