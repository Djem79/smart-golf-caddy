// ios/SmartGolfCaddyWatch/Views/WatchHoleView.swift
// Экран лунки на часах: номер + пар, крупный счётчик ударов, +/-, текущая
// клюшка (тап → WatchClubPicker), навигация лунок, индикатор
// несинхронизированных ударов. Никакого WatchConnectivity — только VM.
import SwiftUI

struct WatchHoleView: View {
    let viewModel: WatchRoundViewModel

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

    private var distanceLabel: String? {
        guard let hole = viewModel.currentHole, hole.distanceMeters > 0 else { return nil }
        let unitsYards = viewModel.snapshot?.units == .yd
        let value = unitsYards ? Score.metersToYards(hole.distanceMeters) : hole.distanceMeters
        return "\(value) \(unitsYards ? "ярд" : "м")"
    }

    /// «Пар N • 300 м» — совмещаем пар и дистанцию лунки в одну строку под
    /// заголовком, чтобы не тратить лишнюю строку экрана (41–46мм — каждая
    /// точка высоты на счету).
    private var holeSubtitle: String {
        guard let par = viewModel.currentHole?.par else { return "" }
        if let distanceLabel {
            return "Пар \(par) • \(distanceLabel)"
        }
        return "Пар \(par)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                holeNavRow

                Text("\(viewModel.shots.count)")
                    .font(DSFont.headlineLG)
                    .foregroundStyle(WatchColor.textPrimary)
                    .accessibilityLabel("Ударов на лунке: \(viewModel.shots.count)")

                shotButtonsRow
                clubRow

                if viewModel.pendingCount > 0 {
                    pendingIndicator
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
        }
        .background(WatchColor.background)
        .navigationTitle(viewModel.snapshot?.courseName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                WatchClubPicker(
                    clubs: viewModel.clubs,
                    selectedClub: viewModel.selectedClub,
                    onSelect: { club in
                        viewModel.selectedClub = club
                        showPicker = false
                    }
                )
            }
        }
    }

    private var holeNavRow: some View {
        HStack {
            Button {
                viewModel.previousHole()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.holeNumber <= 1 ? WatchColor.textSecondary : WatchColor.accent)
            .disabled(viewModel.holeNumber <= 1)
            .frame(width: 44, height: 44)

            Spacer(minLength: 0)

            VStack(spacing: 1) {
                Text("Лунка \(viewModel.holeNumber)")
                    .font(DSFont.titleLG)
                    .foregroundStyle(WatchColor.textPrimary)
                Text(holeSubtitle)
                    .font(DSFont.labelMD)
                    .foregroundStyle(WatchColor.textSecondary)
            }

            Spacer(minLength: 0)

            Button {
                viewModel.nextHole()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.holeNumber >= totalHoles ? WatchColor.textSecondary : WatchColor.accent)
            .disabled(viewModel.holeNumber >= totalHoles)
            .frame(width: 44, height: 44)
        }
    }

    private var shotButtonsRow: some View {
        HStack(spacing: 20) {
            Button {
                viewModel.removeShot()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 46, height: 46)
                    .background(WatchColor.textSecondary.opacity(0.2), in: Circle())
                    .foregroundStyle(WatchColor.textPrimary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.shots.isEmpty)
            .accessibilityLabel("Убрать удар")

            Button {
                viewModel.addShot()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(DSColor.primary, in: Circle())
                    .foregroundStyle(DSColor.onPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Добавить удар")
        }
    }

    private var clubRow: some View {
        Button {
            showPicker = true
        } label: {
            HStack {
                Image(systemName: "figure.golf")
                    .foregroundStyle(WatchColor.accent)
                Text(viewModel.selectedClub ?? "Клюшка")
                    .font(DSFont.labelLG)
                    .foregroundStyle(WatchColor.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(WatchColor.textSecondary)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(WatchColor.textSecondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var pendingIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11))
            Text("Не синхронизировано: \(viewModel.pendingCount)")
                .font(DSFont.labelMD)
        }
        .foregroundStyle(WatchColor.pending)
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
        updatedAt: Date()
    )
    return NavigationStack {
        WatchHoleView(viewModel: WatchRoundViewModel(snapshot: snapshot))
    }
}
