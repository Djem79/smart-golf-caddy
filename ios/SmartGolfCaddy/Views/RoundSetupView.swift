// ios/SmartGolfCaddy/Views/RoundSetupView.swift
import SwiftUI

struct RoundSetupView: View {
    @Environment(SessionViewModel.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(AppStore.self) private var store
    @State private var model = RoundSetupViewModel()
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                nameSection
                holesSection
                teeSection
                if let message = model.errorMessage {
                    Text(message)
                        .font(DSFont.labelLG)
                        .foregroundStyle(DSColor.error)
                        .frame(maxWidth: .infinity)
                }
                DSButton(title: model.creating ? "Создаём..." : "Начать раунд",
                         icon: "flag.fill",
                         disabled: model.creating) {
                    Task {
                        if let roundId = await model.createRound(profile: session.profile) {
                            router.replaceLast(.hole(roundId: roundId, number: 1))
                        }
                    }
                }
            }
            .padding(DS.screenPadding)
        }
        .background(DSColor.surface)
        .navigationTitle("Настройка раунда")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.adopt(store: store) }
    }

    private var sectionHeader: (String) -> Text {
        { title in
            Text(title)
                .font(DSFont.labelLG)
                .tracking(1.2)
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("НАЗВАНИЕ ПОЛЯ")
                .foregroundStyle(DSColor.onSurfaceVariant)
            if model.selectedPlaceId != nil {
                selectedCourseCard
            } else {
                TextField("Например: Гольф клуб Москва", text: $model.courseName)
                    .font(DSFont.bodyMD)
                    .padding(14)
                    .background(DSColor.surfaceContainerLowest)
                    .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.cornerRadius)
                            .stroke(nameFocused ? DSColor.primary : DSColor.outlineVariant)
                    )
                    .focused($nameFocused)
            }
        }
    }

    private var selectedCourseCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.courseName)
                .font(DSFont.titleLG)
                .foregroundStyle(DSColor.onSurface)
            Text("\(model.selectedVicinity) · \(String(format: "%.1f", model.selectedDistanceKm)) км")
                .font(DSFont.labelLG)
                .foregroundStyle(DSColor.onSurfaceVariant)
            Button("Сменить поле") {
                router.replaceLast(.courseSearch)
            }
            .font(DSFont.labelLG)
            .foregroundStyle(DSColor.primary)
            .frame(minHeight: DS.touchTarget)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: DS.cornerRadius).stroke(DSColor.outlineVariant.opacity(0.25)))
    }

    private var holesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("КОЛИЧЕСТВО ЛУНОК")
                .foregroundStyle(DSColor.onSurfaceVariant)
            HStack(spacing: 12) {
                ForEach([9, 18], id: \.self) { n in
                    Button {
                        model.totalHoles = n
                    } label: {
                        Text("\(n)")
                            .font(DSFont.titleLG)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: DS.touchTarget)
                    }
                    .background(model.totalHoles == n ? DSColor.primary : .clear)
                    .foregroundStyle(model.totalHoles == n ? DSColor.onPrimary : DSColor.onSurfaceVariant)
                    .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.cornerRadius)
                            .stroke(model.totalHoles == n ? DSColor.primary : DSColor.outlineVariant, lineWidth: 2)
                    )
                }
            }
        }
    }

    private var teeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("ТИИ (ОТКУДА ИГРАЕМ)")
                .foregroundStyle(DSColor.onSurfaceVariant)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(TeeColor.allCases, id: \.self) { tee in
                    teeCard(tee)
                }
            }
        }
    }

    private func teeCard(_ tee: TeeColor) -> some View {
        let selected = model.tee == tee
        return Button {
            model.tee = tee
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("T")
                    .font(DSFont.labelMD)
                    .foregroundStyle(Color(hex: tee.textHex))
                    .frame(width: 28, height: 28)
                    .background(Color(hex: tee.bgHex))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(DSColor.outlineVariant.opacity(0.4)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tee.label)
                        .font(DSFont.labelLG)
                        .foregroundStyle(DSColor.onSurface)
                    Text(tee.teeDescription)
                        .font(DSFont.labelMD)
                        .foregroundStyle(DSColor.onSurfaceVariant)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(12)
            .background(selected ? DSColor.primaryContainer.opacity(0.1) : DSColor.surfaceContainerLowest)
            .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DS.cornerRadius)
                    .stroke(selected ? DSColor.primary : DSColor.outlineVariant.opacity(0.6), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
