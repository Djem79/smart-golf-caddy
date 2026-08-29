// ios/SmartGolfCaddy/Views/JoinGameView.swift
// Порт JoinGame.tsx: ручной ввод 6-значного кода лобби либо автовход по
// deep-link (`code` пришёл из ссылки/QR) — ровно один раз на код.
import SwiftUI

struct JoinGameView: View {
    let code: String?

    @Environment(AppRouter.self) private var router
    @Environment(SessionViewModel.self) private var session
    @Environment(LocaleManager.self) private var lm
    @State private var model = JoinGameViewModel()
    @FocusState private var codeFieldFocused: Bool

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Image(systemName: "ticket")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(DSColor.primary)
                    .frame(width: 64, height: 64)
                    .background(DSColor.primaryContainer.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.cornerRadiusLG)
                            .stroke(DSColor.primaryContainer.opacity(0.2))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadiusLG))
                Text(lm.t.joinGame.heading)
                    .font(DSFont.headlineMD)
                    .foregroundStyle(DSColor.onSurface)
                Text(lm.t.joinGame.subtitle)
                    .font(DSFont.bodyMD)
                    .foregroundStyle(DSColor.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            .padding(.top, 40)

            TextField("ABCDEF", text: Binding(
                get: { model.code },
                set: { model.setCode($0) }
            ))
            .focused($codeFieldFocused)
            .font(DSFont.headlineLG)
            .tracking(8)
            .multilineTextAlignment(.center)
            .textCase(.uppercase)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.characters)
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            .background(DSColor.surfaceContainerLowest)
            .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DS.cornerRadius)
                    .stroke(DSColor.outlineVariant, lineWidth: 2)
            )
            .accessibilityLabel(lm.t.joinGame.codeAria)

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(DSFont.labelLG)
                    .foregroundStyle(DSColor.error)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                DSButton(
                    title: model.loading ? lm.t.joinGame.connecting : lm.t.joinGame.join,
                    disabled: !model.canSubmit
                ) {
                    codeFieldFocused = false
                    Task {
                        if let roundId = await model.join(profile: session.profile) {
                            router.replaceLast(.lobby(roundId: roundId))
                        }
                    }
                }
                DSButton(title: lm.t.common.cancel, style: .secondary) { router.goHome() }
            }
        }
        .padding(.horizontal, DS.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DSColor.surface)
        .navigationTitle(lm.t.joinGame.navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let joined = await model.autoJoinIfNeeded(initial: code, profile: session.profile) {
                router.replaceLast(.lobby(roundId: joined))
            }
        }
    }
}
