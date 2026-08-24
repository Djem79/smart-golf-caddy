// ios/SmartGolfCaddyWatch/Views/WatchRootView.swift
// Маршрутизация: нет снимка раунда с телефона → плейсхолдер; есть →
// WatchHoleView. Снимок читается из PhoneBridge.latestSnapshot (реальная
// синхронизация/AppDelegate wiring — Task 4, здесь только чтение).
// WatchRoundViewModel держится в @State, чтобы новый снимок применялся
// через apply(snapshot:) (не теряя локальные несинхронизированные удары),
// а не пересоздавал VM с нуля при каждом обновлении.
import SwiftUI

struct WatchRootView: View {
    private let bridge = PhoneBridge.shared

    @State private var viewModel: WatchRoundViewModel?

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
