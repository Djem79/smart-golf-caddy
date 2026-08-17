import SwiftUI

struct AuthView: View {
    @Environment(SessionViewModel.self) private var session

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "figure.golf")
                .font(.system(size: 64))
                .foregroundStyle(DSColor.primary)
            Text("Smart Golf Caddy")
                .font(DSFont.headlineLG)
                .foregroundStyle(DSColor.onSurface)
            Text("Трекинг гольф-раундов")
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
                Text("ВОЙТИ ЧЕРЕЗ GOOGLE")
                    .font(DSFont.labelLG)
                    .tracking(1.5)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DS.touchTarget)
            }
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
