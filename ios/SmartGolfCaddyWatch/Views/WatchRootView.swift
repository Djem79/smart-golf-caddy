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
        }
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
        greens: [:],
        activeHoleNumber: 3,
        units: .m,
        updatedAt: Date()
    )
    #endif
}
