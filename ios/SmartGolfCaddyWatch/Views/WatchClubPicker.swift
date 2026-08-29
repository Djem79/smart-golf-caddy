// ios/SmartGolfCaddyWatch/Views/WatchClubPicker.swift
// Список клюшек крупными строками — под палец на 41–46мм. Выбранная клюшка
// отмечена галочкой. Никакого WatchConnectivity — чистая вью над VM.
import SwiftUI

struct WatchClubPicker: View {
    let clubs: [String]
    let selectedClub: String?
    /// T5 (watch localization): passed in by the caller (WatchHoleView, via
    /// its resolved `strings`) rather than hardcoded — this view has no
    /// access to a snapshot/locale of its own.
    let title: String
    let onSelect: (String) -> Void

    var body: some View {
        List(clubs, id: \.self) { club in
            Button {
                onSelect(club)
            } label: {
                HStack {
                    Text(club)
                        .font(DSFont.titleLG)
                        .foregroundStyle(WatchColor.textPrimary)
                    Spacer()
                    if club == selectedClub {
                        Image(systemName: "checkmark")
                            .foregroundStyle(WatchColor.accent)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(WatchColor.background)
        }
        .listStyle(.carousel)
        .navigationTitle(title)
        .background(WatchColor.background)
    }
}

#Preview {
    NavigationStack {
        WatchClubPicker(
            clubs: ["Driver", "3 Wood", "7 Iron", "PW", "Putter"],
            selectedClub: "7 Iron",
            title: "Club",
            onSelect: { _ in }
        )
    }
}
