// ios/SmartGolfCaddy/Views/HomePlaceholderView.swift
// Временный Home — План 2 заменит полноценным экраном.
import SwiftUI

struct HomePlaceholderView: View {
    @Environment(SessionViewModel.self) private var session

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.crop.circle")
                .font(.system(size: 48))
                .foregroundStyle(DSColor.primary)
            Text("Привет, \(session.profile?.name ?? "…")!")
                .font(DSFont.headlineMD)
                .foregroundStyle(DSColor.onSurface)
            Text("Клюшек в сумке: \(session.profile?.resolvedBag.filter(\.enabled).count ?? 0)")
                .font(DSFont.bodyMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
            #if DEBUG
            DiagnosticsView()
            #endif
            Spacer()
            Button {
                session.signOut()
            } label: {
                Text("ВЫЙТИ")
                    .font(DSFont.labelLG)
                    .tracking(1.5)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DS.touchTarget)
            }
            .background(DSColor.surfaceContainer)
            .foregroundStyle(DSColor.onSurface)
            .clipShape(Capsule())
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.surface)
    }
}
