// ios/SmartGolfCaddyWatch/Views/WatchRootView.swift
// Маршрутизация: нет снимка раунда с телефона → плейсхолдер; есть →
// WatchHoleView. Снимок читается из PhoneBridge.latestSnapshot. Здесь же
// (Task 4) — активация моста и отправка очереди ударов телефону: root-вью
// живёт весь жизненный цикл приложения часов, поэтому это естественная
// точка для активации сессии и подписки на изменения WatchShotQueue —
// WatchHoleView и WatchRoundViewModel остаются без WatchConnectivity.
// WatchRoundViewModel держится в @State, чтобы новый снимок применялся
// через apply(snapshot:) (не теряя локальные несинхронизированные удары),
// а не пересоздавал VM с нуля при каждом обновлении.
import SwiftUI

struct WatchRootView: View {
    private let bridge = PhoneBridge.shared

    @State private var viewModel: WatchRoundViewModel?
    @State private var queueObserver: NSObjectProtocol?
    @State private var staleSyncFailureObserver: NSObjectProtocol?
    @State private var staleSyncFailure: StaleSyncFailure?

    /// T5 (watch localization): same resolution as WatchRoundViewModel.locale
    /// (active snapshot's language, else the watch's system language) — root
    /// view needs its own copy for the placeholder/stale-failure banner,
    /// which render BEFORE any WatchRoundViewModel exists.
    private var t: Strings { Strings.resolved(viewModel?.locale ?? AppLocaleStore.systemDefault) }

    /// Fix 12 (живое ревью Task 4) — квитанция `accepted: false` для
    /// раунда, ОТЛИЧНОГО от текущего снимка часов (типичная трасса: удар
    /// на последней лунке не долетел до завершения раунда, телефон
    /// поставил `finished`, связь восстановилась ПОСЛЕ — сервер отверг
    /// запись как раунд уже неактивный). `WatchRoundViewModel.handleSyncFailed`
    /// такую квитанцию отфильтровывает (roundId не совпадает с текущим
    /// снимком) — молчаливая потеря удара БЕЗ единого сигнала игроку,
    /// именно то, что фаза обязана исключать. Этот баннер — единственное
    /// место, которое ловит квитанции ЛЮБОГО раунда (не только текущего),
    /// живёт на уровне root-вью (весь жизненный цикл приложения, не
    /// привязан к тому, существует ли сейчас VM конкретного раунда).
    struct StaleSyncFailure: Equatable {
        let roundId: String
        let holeNumber: Int
    }

    /// Решение "нужно ли показать баннер" — чистая функция, вынесена из
    /// closure ради тестируемости (WatchRootViewTests.swift — SwiftUI View
    /// в этом проекте напрямую не тестируется, но эта логика может жить
    /// отдельно от неё). Свой ТЕКУЩИЙ раунд уже показан через
    /// WatchHoleView/currentHoleSyncFailed — баннер для него не нужен, не
    /// дублируем. Любой другой roundId (включая nil currentRoundId — нет
    /// активного раунда на экране вовсе) — обязан быть показан, иначе
    /// сигнал теряется молча (Fix 12, живое ревью Task 4).
    static func staleSyncFailure(forRoundId roundId: String, holeNumber: Int, currentRoundId: String?) -> StaleSyncFailure? {
        guard roundId != currentRoundId else { return nil }
        return StaleSyncFailure(roundId: roundId, holeNumber: holeNumber)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    WatchHoleView(viewModel: viewModel)
                } else {
                    placeholder
                }
            }
        }
        .onAppear { syncViewModel(with: bridge.latestSnapshot) }
        .onChange(of: bridge.latestSnapshot) { _, newSnapshot in
            syncViewModel(with: newSnapshot)
        }
        .task {
            bridge.activate()
            // Хвосты, оставшиеся с прошлого запуска (durable-очередь
            // переживает перезапуск часов) — пробуем отправить сразу.
            bridge.flushShotQueue()
            if queueObserver == nil {
                // queue: .main гарантирует исполнение на главном потоке, но
                // компилятору об этом неизвестно — assumeIsolated явно
                // подтверждает MainActor-контекст (тот же приём, что и в
                // HoleTrackerViewModel.start() для .shotQueueDidChange).
                queueObserver = NotificationCenter.default.addObserver(
                    forName: .watchShotQueueDidChange, object: nil, queue: .main
                ) { _ in
                    MainActor.assumeIsolated { bridge.flushShotQueue() }
                }
            }
            if staleSyncFailureObserver == nil {
                staleSyncFailureObserver = NotificationCenter.default.addObserver(
                    forName: .watchShotSyncFailed, object: nil, queue: .main
                ) { notification in
                    MainActor.assumeIsolated {
                        guard let roundId = notification.userInfo?["roundId"] as? String,
                              let hole = notification.userInfo?["holeNumber"] as? Int else { return }
                        // Присваиваем ТОЛЬКО когда решение "показать" — иначе
                        // квитанция по ТЕКУЩЕМУ раунду (nil от функции) могла
                        // бы затереть уже показанный, ещё не закрытый игроком
                        // баннер о ДРУГОМ (более раннем) отклонённом раунде.
                        if let failure = Self.staleSyncFailure(
                            forRoundId: roundId, holeNumber: hole, currentRoundId: viewModel?.snapshot?.roundId
                        ) {
                            staleSyncFailure = failure
                        }
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if let staleSyncFailure {
                staleSyncFailureBanner(staleSyncFailure)
            }
        }
    }

    private func staleSyncFailureBanner(_ failure: StaleSyncFailure) -> some View {
        VStack(spacing: 4) {
            Text(t.watch.staleShotNotSaved(failure.holeNumber))
                .font(DSFont.labelMD)
                .foregroundStyle(WatchColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(t.watch.staleRoundFinished)
                .font(DSFont.labelMD)
                .foregroundStyle(WatchColor.textPrimary.opacity(0.85))
                .multilineTextAlignment(.center)
            Button(t.watch.gotIt) {
                staleSyncFailure = nil
            }
            .buttonStyle(.plain)
            .font(DSFont.labelMD)
            .foregroundStyle(WatchColor.textPrimary)
            .underline()
            .padding(.top, 2)
            .frame(minHeight: 32)  // touch target — узкая кнопка-ссылка на маленьком экране
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(WatchColor.error.opacity(0.92), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(t.watch.staleShotNotSavedAria(failure.holeNumber))
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.golf")
                .font(.system(size: 28))
                .foregroundStyle(WatchColor.accent)
            Text(t.watch.roundNotStarted)
                .font(DSFont.labelLG)
                .foregroundStyle(WatchColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(t.watch.startOnPhone)
                .font(DSFont.labelMD)
                .foregroundStyle(WatchColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WatchColor.background)
    }

    private func syncViewModel(with snapshot: WatchRoundSnapshot?) {
        if let snapshot {
            if let viewModel {
                viewModel.apply(snapshot: snapshot)
            } else {
                viewModel = WatchRoundViewModel(snapshot: snapshot)
            }
            return
        }
        #if DEBUG
        // Превью-фикстура ТОЛЬКО для DEBUG-сборок и только когда реального
        // снимка с телефона ещё нет (Task 4 не подключена / телефон не
        // рядом) — включается launch argument, не показывается сама по
        // себе, чтобы плейсхолдер оставался виден по умолчанию.
        if viewModel == nil, ProcessInfo.processInfo.arguments.contains("-watchPreviewFixture") {
            let args = ProcessInfo.processInfo.arguments
            // T5 (watch localization): -watchPreviewLocaleEN bakes English
            // into the fixture snapshot itself (deterministic — doesn't
            // depend on the simulator's system language) so both languages
            // of the hole screen/club picker can be screenshotted from the
            // same simulator run.
            let locale: AppLocale = args.contains("-watchPreviewLocaleEN") ? .en : .ru
            // Task 6 (компоновка "один экран"): -watchPreviewDistanceUnavailable
            // убирает ВСЕ метки грина из фикстуры — детерминированно даёт «—»
            // в главном элементе экрана (дистанция до центра грина) независимо
            // от того, выдано ли симулятору разрешение на геолокацию. Без этого
            // флага состояние «недоступно» зависело бы от live-GPS симулятора,
            // что ломало бы скриншот-доказательство при перезапуске.
            let withGreenMark = !args.contains("-watchPreviewDistanceUnavailable")
            let fixture = Self.debugFixture(locale: locale, withGreenMark: withGreenMark)
            viewModel = WatchRoundViewModel(snapshot: fixture)

            // -watchPreviewPending / -watchPreviewSyncFailed force the
            // "не синхронизировано" / "не удалось синхронизировать"
            // indicators for screenshot verification — deterministic
            // regardless of leftover state from a previous debug run
            // (WatchShotQueue.shared persists to disk), so the slot is
            // cleared first every time.
            let queue = WatchShotQueue.shared
            queue.enqueue(roundId: fixture.roundId, holeNumber: fixture.activeHoleNumber, clubs: [])
            viewModel?.selectedClub = nil
            if args.contains("-watchPreviewPending") {
                // "7 Iron" (не безымянный дефолт) — Fix 1, живое ревью task 6:
                // владелец явно требует, чтобы выбранная клюшка была ВИДНА на
                // скриншоте «счёт > 0», а не оставалась плейсхолдером. В
                // реальном флоу selectedClub выставляет пикер (WatchClubPicker);
                // здесь эмулируем тот же результат для детерминированного
                // скриншот-доказательства.
                queue.enqueue(roundId: fixture.roundId, holeNumber: fixture.activeHoleNumber, clubs: ["7 Iron"])
                viewModel?.selectedClub = "7 Iron"
            }
            if args.contains("-watchPreviewSyncFailed") {
                queue.markConfirmed(roundId: fixture.roundId, holeNumber: fixture.activeHoleNumber, acceptedCount: 0, accepted: false)
            }
        }
        #endif
    }

    #if DEBUG
    private static func debugFixture(locale: AppLocale, withGreenMark: Bool = true) -> WatchRoundSnapshot {
        WatchRoundSnapshot(
            roundId: "debug-preview",
            courseName: "Pebble Beach",
            totalHoles: 18,
            holes: (1...18).map {
                WatchHole(number: $0, par: [3, 4, 4, 5].randomElement() ?? 4,
                          distanceMeters: 280 + $0 * 4, myShots: $0 < 3 ? 4 : 0)
            },
            clubs: ["Driver", "3 Wood", "5 Iron", "7 Iron", "PW", "Putter"],
            // Метка грина лунки 3 — ~78 м к северу от координаты, которую
            // ставит live-проверка через `xcrun simctl location` (см.
            // task-5-report.md). Только для этой лунки: остальные остаются без
            // метки. -watchPreviewDistanceUnavailable (Task 6) убирает и её —
            // детерминированное «—» в главном элементе экрана без зависимости
            // от live-GPS симулятора.
            greens: withGreenMark ? [3: GreenMark(lat: 37.335600, lng: -122.009020)] : [:],
            activeHoleNumber: 3,
            units: .m,
            locale: locale,
            updatedAt: Date()
        )
    }
    #endif
}
