// ios/SmartGolfCaddy/Views/HoleTrackerView.swift
import SwiftUI
import UIKit

struct HoleTrackerView: View {
    let roundId: String
    let holeNumber: Int

    @Environment(SessionViewModel.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(AppStore.self) private var store
    @State private var model: HoleTrackerViewModel
    @State private var selectedClub: String = "Driver"
    @State private var showFinishConfirm = false
    @State private var showHoleEditor = false
    @State private var savingHole = false

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
                    DSButton(title: "На главную", style: .secondary) { router.popToRoot() }
                        .padding(.horizontal, 48)
                }
                .padding(DS.screenPadding)
            } else {
                ProgressView("Загрузка...")
            }
        }
        .background(DSColor.surface)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Лунка \(holeNumber) / \(model.round?.totalHoles ?? 0)")
                    .font(DSFont.titleLG)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    router.goHome()
                } label: {
                    Image(systemName: "house")
                }
                .accessibilityLabel("На главную")
            }
        }
        .task {
            selectedClub = store.lastClubUsed
            let ids = pickerClubs.map(\.id)
            if !ids.contains(selectedClub) && selectedClub != Clubs.penaltyId { selectedClub = ids.first ?? "Driver" }
            model.start()
        }
        .onChange(of: model.round?.status) { _, status in
            if status == .finished {
                router.replaceLast(.results(roundId: roundId))
            }
        }
        .confirmationDialog("Закончить игру?", isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button("Завершить", role: .destructive) {
                Task {
                    if await model.finish() {
                        router.replaceLast(.results(roundId: roundId))
                    }
                }
            }
            Button("Продолжить", role: .cancel) {}
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
            }
        }
    }

    private var finishConfirmBody: String {
        guard let round = model.round else { return "" }
        if holeNumber < round.totalHoles {
            return "Вы прошли \(holeNumber - 1) из \(round.totalHoles) лунок. Пройденные удары попадут в итоги, незавершённые лунки — без ударов."
        }
        return "Раунд будет записан в историю. Изменить удары после этого нельзя."
    }

    @ViewBuilder
    private func content(round: Round, hole: HoleConfig) -> some View {
        VStack(spacing: 0) {
            holeHeader(round: round, hole: hole)
            ScrollView {
                VStack(spacing: 24) {
                    counter
                    if !model.currentClubs.isEmpty { series }
                    if let saveError = model.saveError {
                        Text(saveError)
                            .font(DSFont.labelLG)
                            .foregroundStyle(DSColor.error)
                    }
                    if model.hasQueuedShots {
                        Label("Нет сети — удары сохранятся автоматически", systemImage: "wifi.slash")
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
                    Text("Пар")
                        .font(DSFont.labelLG)
                        .foregroundStyle(DSColor.onPrimary.opacity(0.7))
                    Text("\(hole.par)")
                        .font(DSFont.headlineMD)
                        .foregroundStyle(DSColor.onPrimary)
                        .underline(model.isHost, pattern: .dot)
                }
            }
            .disabled(!model.isHost)
            .accessibilityLabel("Изменить пар лунки (сейчас \(hole.par))")
            Spacer()
            Text("\(holeNumber)")
                .font(DSFont.displayLG)
                .foregroundStyle(DSColor.onPrimary)
            Spacer()
            Button {
                if model.isHost { showHoleEditor = true }
            } label: {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Дист.")
                        .font(DSFont.labelLG)
                        .foregroundStyle(DSColor.onPrimary.opacity(0.7))
                    HStack(spacing: 6) {
                        Text("\(hole.distanceMeters) м")
                            .font(DSFont.headlineMD)
                            .foregroundStyle(DSColor.onPrimary)
                            .underline(model.isHost, pattern: .dot)
                        Circle()
                            .fill(Color(hex: round.tee.bgHex))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(DSColor.onPrimary.opacity(0.3)))
                            .accessibilityLabel("Тии: \(round.tee.label)")
                    }
                }
            }
            .disabled(!model.isHost)
            .accessibilityLabel("Изменить дистанцию лунки (сейчас \(hole.distanceMeters) метров)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(DSColor.primaryContainer)
    }

    private var counter: some View {
        VStack(spacing: 12) {
            Text("ВАШИ УДАРЫ")
                .font(DSFont.labelLG)
                .tracking(1.5)
                .foregroundStyle(DSColor.onSurfaceVariant)
            HStack(spacing: 40) {
                Button {
                    haptics.impactOccurred()
                    let clubs = model.currentClubs
                    guard !clubs.isEmpty else { return }
                    let newClubs = Array(clubs.dropLast())
                    Task {
                        if await model.save(newClubs), let last = newClubs.last {
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
                    Task {
                        if await model.save(newClubs), let last = newClubs.last {
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
            Text("УДАРЫ")
                .font(DSFont.labelMD)
                .tracking(3)
                .foregroundStyle(DSColor.onSurfaceVariant)
        }
    }

    private var series: some View {
        VStack(spacing: 6) {
            Text("Серия ударов")
                .font(DSFont.labelMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
            FlowLayoutCompat(items: Array(model.currentClubs.enumerated()), spacing: 6) { index, club in
                Text(model.currentDistances.indices.contains(index) && model.currentDistances[index] > 0
                     ? "\(index + 1). \(Clubs.label(for: club, in: fullBag)) · \(model.currentDistances[index]) м"
                     : "\(index + 1). \(Clubs.label(for: club, in: fullBag))")
                    .font(DSFont.labelMD)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(DSColor.surfaceContainer)
                    .foregroundStyle(DSColor.onSurfaceVariant)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, DS.screenPadding)
            Label(model.gpsReady ? "GPS готов — дистанции пишутся" : "Ждём GPS — дистанции не пишутся",
                  systemImage: model.gpsReady ? "location.fill" : "location.slash")
                .font(DSFont.labelMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
        }
    }

    private var clubPicker: some View {
        VStack(spacing: 8) {
            Text("ВЫБОР КЛЮШКИ")
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
                DSButton(title: "Пред.", icon: "chevron.left", style: .secondary,
                         disabled: holeNumber == 1) {
                    router.replaceLast(.hole(roundId: roundId, number: holeNumber - 1))
                }
                if holeNumber < round.totalHoles {
                    DSButton(title: "Дальше", icon: "chevron.right") {
                        router.replaceLast(.hole(roundId: roundId, number: holeNumber + 1))
                    }
                } else {
                    DSButton(title: "Закончить игру", icon: "flag.fill",
                             disabled: model.finishing) {
                        showFinishConfirm = true
                    }
                }
            }
            if model.isHost && holeNumber < round.totalHoles {
                DSButton(title: "Закончить игру досрочно", icon: "flag", style: .secondary,
                         disabled: model.finishing) {
                    showFinishConfirm = true
                }
            }
        }
        .padding(.horizontal, DS.screenPadding)
        .padding(.bottom, 12)
    }
}
