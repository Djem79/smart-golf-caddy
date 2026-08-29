// ios/SmartGolfCaddyWatch/Views/WatchHoleView.swift
// Экран лунки на часах — распашка Garmin-стиля: дистанция до ЦЕНТРА
// грина (не до флага — его переставляют ежедневно) главный элемент
// экрана, номер лунки/пар мелкие подписи сверху. Запись удара и счёт
// остаются на этом же экране компактно (в отличие от Garmin, где они
// уведены в меню) — это ядро приложения. ВСЁ помещается на 41мм и 46мм
// БЕЗ прокрутки — никакого ScrollView здесь быть не должно.
// Никакого WatchConnectivity — только VM.
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

    /// Крупное число — дистанция до ЦЕНТРА грина текущей лунки. «—» когда
    /// метки грина для этой лунки в снимке нет ИЛИ GPS-фикс негоден
    /// (устарел/неточен/отсутствует) — см. WatchRoundViewModel.greenDistanceMeters
    /// (единый nil-путь для обоих случаев). НИКОГДА не «0» и не
    /// устаревшее значение — задание владельца прямо это требует, т.к.
    /// «—» в дистанции читается игроком как «сейчас недостоверно», а «0»
    /// выглядело бы как реальный замер.
    private var greenDistanceValue: String {
        guard let meters = viewModel.greenDistanceMeters else { return "—" }
        let value = unitsYards ? Score.metersToYards(meters) : meters
        return "\(value)"
    }

    /// Мелкая подпись под крупным числом: «м до центра грина» / «yd to
    /// green center». Показывается ВСЕГДА (в отличие от прежней версии,
    /// где вся строка пряталась при отсутствии метки грина) — теперь это
    /// главный элемент экрана и его якорь не должен прыгать в зависимости
    /// от того, размечено ли поле.
    private var greenDistanceCaption: String { t.watch.toGreenCenterCaption(unitLabel) }

    private var greenDistanceAria: String {
        guard viewModel.greenDistanceMeters != nil else { return t.watch.toGreenCenterUnavailableAria }
        return t.watch.toGreenCenterAria("\(greenDistanceValue) \(unitLabel)")
    }

    var body: some View {
        VStack(spacing: 2) {
            holeNavRow

            Text(parLabel)
                .font(DSFont.labelMD)
                .foregroundStyle(WatchColor.textSecondary)

            Spacer(minLength: 0)

            VStack(spacing: 0) {
                Text(greenDistanceValue)
                    .font(DSFont.displayLG)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(WatchColor.textPrimary)
                Text(greenDistanceCaption)
                    .font(DSFont.labelMD)
                    .foregroundStyle(WatchColor.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(greenDistanceAria)

            Spacer(minLength: 0)

            Rectangle()
                .fill(WatchColor.textSecondary.opacity(0.25))
                .frame(height: 1)
                .padding(.horizontal, 4)

            shotRow
            clubRow
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WatchColor.background)
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

    /// «Пар N» — без общей дистанции лунки и без названия поля (оба
    /// убраны по запросу владельца: имя курса нигде на этом экране не
    /// показывается, а место, которое занимала строка «Пар • дистанция»,
    /// теперь отдано под дистанцию до центра грина).
    private var parLabel: String {
        guard let par = viewModel.currentHole?.par else { return "" }
        return "\(t.common.par) \(par)"
    }

    private var holeNavRow: some View {
        HStack {
            Button {
                viewModel.previousHole()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.holeNumber <= 1 ? WatchColor.textSecondary : WatchColor.accent)
            .disabled(viewModel.holeNumber <= 1)
            .frame(width: 32, height: 32)

            Spacer(minLength: 0)

            Text(t.holeTracker.holeTitleNoTotal(viewModel.holeNumber))
                .font(DSFont.labelLG)
                .foregroundStyle(WatchColor.textPrimary)

            Spacer(minLength: 0)

            Button {
                viewModel.nextHole()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.holeNumber >= totalHoles ? WatchColor.textSecondary : WatchColor.accent)
            .disabled(viewModel.holeNumber >= totalHoles)
            .frame(width: 32, height: 32)
        }
    }

    /// Счёт лунки МЕЖДУ кнопками ⊖/⊕ (не отдельной строкой сверху, как
    /// раньше) — экономит целую строку высоты, требование владельца.
    /// Подпись «ударов»/«shots» под числом убрана (избыточна рядом с
    /// самими кнопками) — счёт озвучивается только через accessibilityLabel.
    private var shotRow: some View {
        HStack(spacing: 12) {
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
                .font(DSFont.headlineMD)
                .monospacedDigit()
                .frame(minWidth: 30)
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

    /// Строка клюшки несёт и индикатор синхронизации — компактная точка/
    /// иконка ВНУТРИ существующей строки (не отдельной строкой) экономит
    /// вертикальное место, при этом индикатор остаётся видимым, как
    /// требует владелец. Приоритет: окончательный отказ синхронизации >
    /// «не синхронизировано» (не одновременно — тот же приоритет, что был
    /// у прежних полноразмерных индикаторов).
    private var clubRow: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "figure.golf")
                    .foregroundStyle(WatchColor.accent)
                Text(viewModel.selectedClub ?? t.common.missingCustomClub)
                    .font(DSFont.labelLG)
                    .foregroundStyle(WatchColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                syncStatusDot
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(WatchColor.textSecondary)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: DS.touchTarget)
            .background(WatchColor.textSecondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(clubRowAccessibilityLabel)
    }

    @ViewBuilder
    private var syncStatusDot: some View {
        if viewModel.currentHoleSyncFailed {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(WatchColor.error)
        } else if viewModel.pendingCount > 0 {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12))
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
