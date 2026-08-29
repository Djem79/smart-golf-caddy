import SwiftUI

struct AuthView: View {
    @Environment(SessionViewModel.self) private var session
    @Environment(LocaleManager.self) private var lm

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "figure.golf")
                .font(.system(size: 64))
                .foregroundStyle(DSColor.primary)
            Text("Smart Golf Caddy")
                .font(DSFont.headlineLG)
                .foregroundStyle(DSColor.onSurface)
            Text(lm.t.auth.tagline)
                .font(DSFont.bodyMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
            Spacer()
            if let message = session.errorMessage {
                Text(message)
                    .font(DSFont.labelMD)
                    .foregroundStyle(DSColor.error)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.screenPadding)
            }
            Button {
                Task { await session.signIn() }
            } label: {
                if session.isSigningIn {
                    ProgressView()
                        .tint(DSColor.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: DS.touchTarget)
                } else {
                    Text(lm.t.auth.signInWithGoogle)
                        .font(DSFont.labelLG)
                        .tracking(1.5)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: DS.touchTarget)
                }
            }
            .disabled(session.isSigningIn)
            .background(DSColor.primary)
            .foregroundStyle(DSColor.onPrimary)
            .clipShape(Capsule())
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.surface)
    }
}
