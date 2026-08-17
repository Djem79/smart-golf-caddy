// ios/SmartGolfCaddy/Views/Components/DSButton.swift
// Аналог веб-компонента Button: full-width капсула, uppercase, иконка слева.
import SwiftUI

struct DSButton: View {
    enum Style {
        case primary, secondary
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
        .background(style == .primary ? DSColor.primary : DSColor.surfaceContainer)
        .foregroundStyle(style == .primary ? DSColor.onPrimary : DSColor.onSurface)
        .clipShape(Capsule())
        .opacity(disabled ? 0.5 : 1)
        .disabled(disabled)
    }
}
