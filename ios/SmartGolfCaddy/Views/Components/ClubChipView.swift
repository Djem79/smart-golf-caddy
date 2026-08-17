// ios/SmartGolfCaddy/Views/Components/ClubChipView.swift
import SwiftUI

struct ClubChipView: View {
    let label: String
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(DSFont.labelLG)
                .padding(.horizontal, 16)
                .frame(minHeight: DS.touchTarget)
        }
        .background(selected ? DSColor.primary : DSColor.surfaceContainerLowest)
        .foregroundStyle(selected ? DSColor.onPrimary : DSColor.onSurface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(selected ? DSColor.primary : DSColor.outlineVariant.opacity(0.6)))
    }
}
