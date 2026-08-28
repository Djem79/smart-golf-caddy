// ios/SmartGolfCaddy/Views/Components/DSButton.swift
// Аналог веб-компонента Button: full-width капсула, uppercase, иконка слева.
import SwiftUI

struct DSButton: View {
    enum Style {
        case primary, secondary
        // Опасные действия (удаление аккаунта и т.п.). Outlined, не filled —
        // тот же вес, что у `secondary`, чтобы не конкурировать с primary CTA
        // на экране, но читается однозначно как "опасно" (аналог web `danger`).
        case destructive
    }

    let title: String
    var icon: String? = nil
    var style: Style = .primary
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(DSFont.labelLG)
                    .tracking(1.5)
            }
            .textCase(.uppercase)
            .frame(maxWidth: .infinity)
            .frame(minHeight: DS.touchTarget)
        }
        .background(background)
        .foregroundStyle(foreground)
        .overlay(
            Capsule().stroke(style == .destructive ? DSColor.error.opacity(0.4) : .clear, lineWidth: 1)
        )
        .clipShape(Capsule())
        .opacity(disabled ? 0.5 : 1)
        .disabled(disabled)
    }

    private var background: Color {
        switch style {
        case .primary: DSColor.primary
        case .secondary: DSColor.surfaceContainer
        case .destructive: DSColor.surfaceContainerLowest
        }
    }

    private var foreground: Color {
        switch style {
        case .primary: DSColor.onPrimary
        case .secondary: DSColor.onSurface
        case .destructive: DSColor.error
        }
    }
}
