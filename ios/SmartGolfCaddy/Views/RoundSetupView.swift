// ios/SmartGolfCaddy/Views/RoundSetupView.swift
import SwiftUI

struct RoundSetupView: View {
    @Environment(SessionViewModel.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(AppStore.self) private var store
    @Environment(LocaleManager.self) private var lm
    @State private var model = RoundSetupViewModel()
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                nameSection
                holesSection
                teeSection
                modeSection
                formatSection
                if let message = model.errorMessage {
                    Text(message)
                        .font(DSFont.labelLG)
                        .foregroundStyle(DSColor.error)
                        .frame(maxWidth: .infinity)
                }
                DSButton(title: model.creating ? lm.t.roundSetup.creating : lm.t.roundSetup.startRound,
                         icon: "flag.fill",
                         disabled: model.creating) {
                    Task {
                        if let roundId = await model.createRound(profile: session.profile) {
                            router.replaceLast(model.mode == .group
                                               ? .lobby(roundId: roundId)
                                               : .hole(roundId: roundId, number: 1))
                        }
                    }
                }
            }
            .padding(DS.screenPadding)
        }
        .background(DSColor.surface)
        .navigationTitle(lm.t.roundSetup.title)
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
            sectionHeader(lm.t.roundSetup.courseNameSectionHeader)
                .foregroundStyle(DSColor.onSurfaceVariant)
            if model.selectedPlaceId != nil {
                selectedCourseCard
            } else {
                TextField(lm.t.roundSetup.courseNamePlaceholder, text: $model.courseName)
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
            Text("\(model.selectedVicinity) · \(String(format: "%.1f", model.selectedDistanceKm)) \(lm.t.common.km)")
                .font(DSFont.labelLG)
                .foregroundStyle(DSColor.onSurfaceVariant)
            Button(lm.t.roundSetup.changeCourse) {
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
            sectionHeader(lm.t.roundSetup.holesSectionHeader)
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
            sectionHeader(lm.t.roundSetup.teeSectionHeader)
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

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(lm.t.roundSetup.modeSectionHeader).foregroundStyle(DSColor.onSurfaceVariant)
            HStack(spacing: 12) {
                choiceCard(title: lm.t.roundSetup.soloTitle, subtitle: lm.t.roundSetup.soloDesc,
                           icon: "person", selected: model.mode == .solo) { model.mode = .solo }
                choiceCard(title: lm.t.roundSetup.groupTitle, subtitle: lm.t.roundSetup.groupDesc,
                           icon: "person.2", selected: model.mode == .group) { model.mode = .group }
            }
            if model.mode == .group {
                Text(lm.t.roundSetup.groupHint)
                    .font(DSFont.labelMD)
                    .foregroundStyle(DSColor.onSurfaceVariant)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var formatSection: some View {
        if model.mode == .group {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(lm.t.roundSetup.formatSectionHeader).foregroundStyle(DSColor.onSurfaceVariant)
                HStack(spacing: 12) {
                    choiceCard(title: lm.t.roundSetup.strokeTitle, subtitle: lm.t.roundSetup.strokeDesc,
                               icon: "chart.bar", selected: model.playMode == .stroke) { model.playMode = .stroke }
                    choiceCard(title: lm.t.roundSetup.matchTitle, subtitle: lm.t.roundSetup.matchDesc,
                               icon: "flag.2.crossed", selected: model.playMode == .match) { model.playMode = .match }
                }
                if model.playMode == .match {
                    Text(lm.t.roundSetup.matchHint)
                        .font(DSFont.labelMD)
                        .foregroundStyle(DSColor.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func choiceCard(title: String, subtitle: String, icon: String,
                            selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? DSColor.primary : DSColor.onSurfaceVariant)
                Text(title).font(DSFont.labelLG).foregroundStyle(DSColor.onSurface)
                Text(subtitle).font(DSFont.labelMD).foregroundStyle(DSColor.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .padding(12)
            .background(selected ? DSColor.primaryContainer.opacity(0.1) : DSColor.surfaceContainerLowest)
            .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: DS.cornerRadius)
                .stroke(selected ? DSColor.primary : DSColor.outlineVariant.opacity(0.6), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}
