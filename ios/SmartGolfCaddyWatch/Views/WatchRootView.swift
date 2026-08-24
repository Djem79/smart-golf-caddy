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
            Text("Лунка \(failure.holeNumber): удар не сохранён")
                .font(DSFont.labelMD)
                .foregroundStyle(WatchColor.textPrimary)
                .multilineTextAlignment(.center)
            Text("Раунд уже завершён")
                .font(DSFont.labelMD)
                .foregroundStyle(WatchColor.textPrimary.opacity(0.85))
                .multilineTextAlignment(.center)
            Button("Понятно") {
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
        .accessibilityLabel("Удар на лунке \(failure.holeNumber) не сохранён — раунд уже завершён")
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.golf")
                .font(.system(size: 28))
                .foregroundStyle(WatchColor.accent)
            Text("Раунд не начат")
                .font(DSFont.labelLG)
                .foregroundStyle(WatchColor.textPrimary)
                .multilineTextAlignment(.center)
            Text("Начните раунд на телефоне")
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
            viewModel = WatchRoundViewModel(snapshot: Self.debugFixture)
        }
        #endif
    }

    #if DEBUG
    private static let debugFixture = WatchRoundSnapshot(
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
        // метки, чтобы live-проверка заодно подтвердила скрытие строки
        // «До грина» там, где метки нет.
        greens: [3: GreenMark(lat: 37.335600, lng: -122.009020)],
        activeHoleNumber: 3,
        units: .m,
        updatedAt: Date()
    )
    #endif
}
