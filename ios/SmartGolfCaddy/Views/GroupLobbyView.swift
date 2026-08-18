// ios/SmartGolfCaddy/Views/GroupLobbyView.swift
// Порт GroupLobby.tsx: код лобби (тап-копировать), QR со ссылкой,
// список игроков, старт хостом, выход с подтверждением.
import SwiftUI
import UIKit

struct GroupLobbyView: View {
    let roundId: String

    @Environment(AppRouter.self) private var router
    @State private var model = GroupLobbyViewModel()
    @State private var copiedCode = false
    @State private var copiedLink = false
    @State private var showLeaveConfirm = false
    @State private var leaving = false

    var body: some View {
        Group {
            if let round = model.round {
                content(round)
            } else if let loadError = model.loadError {
                VStack(spacing: 16) {
                    Text(loadError)
                        .font(DSFont.bodyMD)
                        .foregroundStyle(DSColor.error)
                        .multilineTextAlignment(.center)
                    DSButton(title: "На главную", style: .secondary) { router.goHome() }
                        .padding(.horizontal, 48)
                }
                .padding(DS.screenPadding)
            } else {
                ProgressView("Загрузка лобби...")
            }
        }
        .background(DSColor.surface)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Лобби группы").font(DSFont.titleLG)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button { router.goHome() } label: { Image(systemName: "house") }
                    .accessibilityLabel("На главную")
            }
        }
        .task { model.start(roundId: roundId) }
        .onChange(of: model.round?.status) { _, status in
            guard let status else { return }
            if status == .active {
                router.replaceLast(.hole(roundId: roundId, number: 1))
            } else if status == .finished {
                router.replaceLast(.results(roundId: roundId))
            }
        }
        .confirmationDialog(
            "Покинуть лобби?", isPresented: $showLeaveConfirm, titleVisibility: .visible
        ) {
            Button("Покинуть") {
                Task {
                    leaving = true
                    let ok = await model.leave()
                    leaving = false
                    if ok { router.goHome() }
                }
            }
            Button("Остаться", role: .cancel) {}
        } message: {
            Text(model.isHost
                 ? "Вы хост — без вас раунд не запустится. Лобби останется доступным по коду, но другим игрокам придётся ждать."
                 : "Вы выйдете из этого лобби. Можно вернуться по коду.")
        }
    }

    private func joinURL(_ round: Round) -> String {
        "smartgolfcaddy://join/\(round.lobbyCode)"
    }

    private func content(_ round: Round) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text(round.courseName)
                            .font(DSFont.labelMD)
                            .tracking(1.5)
                            .textCase(.uppercase)
                            .foregroundStyle(DSColor.onSurfaceVariant)
                        Text("\(round.totalHoles) \(pluralRu(round.totalHoles, "лунка", "лунки", "лунок"))")
                            .font(DSFont.labelMD)
                            .foregroundStyle(DSColor.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                    codeCard(round)
                    qrCard(round)
                    playersSection(round)

                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .font(DSFont.labelLG)
                            .foregroundStyle(DSColor.error)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, DS.screenPadding)
                .padding(.bottom, 12)
            }
            actions(round)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(DSColor.surfaceContainerLowest)
            .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: DS.cornerRadius).stroke(DSColor.outlineVariant.opacity(0.25)))
    }

    private func codeCard(_ round: Round) -> some View {
        card {
            Text("Код лобби")
                .font(DSFont.labelMD)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(DSColor.onSurfaceVariant)
                .frame(maxWidth: .infinity)
            Button {
                copyToClipboard(round.lobbyCode, flag: $copiedCode)
            } label: {
                Text(round.lobbyCode)
                    .font(DSFont.bold(34))
                    .tracking(6)
                    .foregroundStyle(DSColor.primary)
                    .frame(maxWidth: .infinity, minHeight: DS.touchTarget)
            }
            .accessibilityLabel("Код лобби \(round.lobbyCode), тап чтобы скопировать")
            HStack(spacing: 4) {
                Image(systemName: copiedCode ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: copiedCode ? .bold : .regular))
                Text(copiedCode ? "Скопировано" : "Тап чтобы скопировать")
                    .font(DSFont.labelMD)
            }
            .foregroundStyle(copiedCode ? DSColor.primary : DSColor.onSurfaceVariant)
            .frame(maxWidth: .infinity)
        }
    }

    private func qrCard(_ round: Round) -> some View {
        card {
            Text("Или отсканируйте QR")
                .font(DSFont.labelMD)
                .tracking(1.5)
                .textCase(.uppercase)
                .foregroundStyle(DSColor.onSurfaceVariant)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)
            QRCodeView(text: joinURL(round), size: 200)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(DSColor.surfaceContainerLowest)
                .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: DS.cornerRadius).stroke(DSColor.outlineVariant.opacity(0.4)))
            Button {
                copyToClipboard(joinURL(round), flag: $copiedLink)
            } label: {
                Text(copiedLink ? "Скопировано" : "Скопировать ссылку")
                    .font(DSFont.labelLG)
                    .foregroundStyle(DSColor.primary)
                    .frame(maxWidth: .infinity, minHeight: DS.touchTarget)
            }
            .padding(.top, 8)
        }
    }

    private func playersSection(_ round: Round) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline) {
                Text("Игроки")
                    .font(DSFont.titleLG)
                    .foregroundStyle(DSColor.onSurface)
                Spacer()
                Text("\(model.players.count)")
                    .font(DSFont.labelMD)
                    .foregroundStyle(DSColor.onSurfaceVariant)
            }
            VStack(spacing: 8) {
                ForEach(model.players, id: \.uid) { uid, info in
                    playerRow(uid: uid, info: info, round: round)
                }
            }
        }
    }

    private func playerRow(uid: String, info: PlayerInfo, round: Round) -> some View {
        card {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(DSColor.primaryContainer)
                Text(info.name)
                    .font(DSFont.bodyMD)
                    .foregroundStyle(DSColor.onSurface)
                    .lineLimit(1)
                Spacer()
                if uid == round.hostId {
                    badge("Хост")
                } else if uid == AuthService.currentUserId {
                    Text("Вы")
                        .font(DSFont.labelMD)
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(DSColor.onSurfaceVariant)
                }
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(DSFont.labelMD)
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(DSColor.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DSColor.primaryContainer.opacity(0.15))
            .clipShape(Capsule())
    }

    private func actions(_ round: Round) -> some View {
        VStack(spacing: 10) {
            if model.isHost {
                DSButton(
                    title: model.starting
                        ? "Запускаем..."
                        : "Начать раунд (\(model.players.count) \(pluralRu(model.players.count, "игрок", "игрока", "игроков")))",
                    icon: "play.fill",
                    disabled: model.starting || model.players.isEmpty
                ) {
                    Task { await model.startRound() }
                }
            } else {
                Text("Ожидаем хоста...")
                    .font(DSFont.bodyMD)
                    .foregroundStyle(DSColor.onSurfaceVariant)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            DSButton(title: "Покинуть лобби", style: .secondary, disabled: leaving) {
                showLeaveConfirm = true
            }
        }
        .padding(.horizontal, DS.screenPadding)
        .padding(.bottom, 16)
    }

    private func copyToClipboard(_ text: String, flag: Binding<Bool>) {
        UIPasteboard.general.string = text
        flag.wrappedValue = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            flag.wrappedValue = false
        }
    }
}
