// ios/SmartGolfCaddy/Views/MyBagView.swift
import SwiftUI

struct MyBagView: View {
    @Environment(SessionViewModel.self) private var session
    @Environment(LocaleManager.self) private var lm
    @State private var model = MyBagViewModel()
    @State private var addingCategory: ClubCategory?
    @State private var reordering = false

    var body: some View {
        List {
            Section {
                counterCard
                    .listRowInsets(EdgeInsets(top: 8, leading: DS.screenPadding, bottom: 4, trailing: DS.screenPadding))
                    .listRowSeparator(.hidden)
                unitsToggle
                    .listRowInsets(EdgeInsets(top: 4, leading: DS.screenPadding, bottom: 4, trailing: DS.screenPadding))
                    .listRowSeparator(.hidden)
                if let message = model.errorMessage {
                    Text(message)
                        .font(DSFont.labelLG)
                        .foregroundStyle(DSColor.error)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                }
            }
            .listRowBackground(DSColor.surface)

            ForEach(Clubs.groups, id: \.category) { group in
                Section {
                    ForEach(model.clubsInGroup(group.category)) { club in
                        ClubRowView(
                            club: club,
                            units: model.units,
                            distanceValue: model.distanceValue(for: club),
                            isPutter: Clubs.category(of: club) == .putter,
                            onToggle: { Task { await model.toggle(id: club.id) } },
                            onSetName: { name in Task { await model.setName(id: club.id, name: name) } },
                            onSetDistance: { raw in Task { await model.setDistance(id: club.id, raw: raw) } }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if club.custom == true {
                                Button(role: .destructive) {
                                    Task { await model.deleteClub(id: club.id) }
                                } label: {
                                    Label(lm.t.common.delete, systemImage: "trash")
                                }
                            }
                        }
                    }
                    .onMove { source, destination in
                        Task { await model.moveClub(inCategory: group.category, from: source, to: destination) }
                    }
                    Button {
                        addingCategory = group.category
                    } label: {
                        Label(lm.t.myBag.addClub, systemImage: "plus")
                            .font(DSFont.labelLG)
                            .foregroundStyle(DSColor.primary)
                            .frame(maxWidth: .infinity, minHeight: DS.touchTarget)
                    }
                } header: {
                    HStack {
                        Text(Clubs.categoryLabel(group.category))
                            .font(DSFont.titleLG)
                            .foregroundStyle(DSColor.onSurface)
                        Spacer()
                        Text("\(model.clubsInGroup(group.category).filter(\.enabled).count)/\(model.clubsInGroup(group.category).count)")
                            .font(DSFont.labelMD)
                            .foregroundStyle(DSColor.onSurfaceVariant)
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DSColor.surface)
        .environment(\.editMode, .constant(reordering ? .active : .inactive))
        .navigationTitle(lm.t.myBag.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if model.saving {
                    Text(lm.t.myBag.saving)
                        .font(DSFont.labelMD)
                        .foregroundStyle(DSColor.onSurfaceVariant)
                } else {
                    Button(reordering ? lm.t.myBag.reorderDone : lm.t.myBag.reorder) {
                        reordering.toggle()
                    }
                    .font(DSFont.labelLG)
                }
            }
        }
        .task { model.syncFromProfile(session.profile) }
        .onChange(of: session.profile) { _, profile in
            model.syncFromProfile(profile)
        }
        .sheet(item: $addingCategory) { category in
            AddClubSheet(category: category, units: model.units) { name, distance in
                Task {
                    await model.addCustomClub(category: category, name: name, distance: distance)
                    addingCategory = nil
                }
            } onCancel: {
                addingCategory = nil
            }
        }
    }

    private var counterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lm.t.myBag.bagComposition)
                        .font(DSFont.headlineMD)
                        .foregroundStyle(DSColor.primary)
                    Text(lm.t.myBag.ruleHint)
                        .font(DSFont.labelMD)
                        .foregroundStyle(DSColor.onSurfaceVariant)
                }
                Spacer()
                Text("\(model.enabledCount)")
                    .font(DSFont.displayLG)
                    .foregroundStyle(DSColor.primary)
                    .monospacedDigit()
                + Text("/\(MyBagViewModel.totalSlots)")
                    .font(DSFont.titleLG)
                    .foregroundStyle(DSColor.onSurfaceVariant)
            }
            GeometryReader { geo in
                Capsule()
                    .fill(DSColor.primary)
                    .frame(width: geo.size.width * CGFloat(min(model.enabledCount, MyBagViewModel.totalSlots)) / CGFloat(MyBagViewModel.totalSlots))
            }
            .frame(height: 8)
            .background(Capsule().fill(DSColor.surfaceContainerHigh))
            if model.enabledCount < MyBagViewModel.totalSlots {
                Text(lm.t.myBag.freeSlots(MyBagViewModel.totalSlots - model.enabledCount))
                    .font(DSFont.labelMD)
                    .foregroundStyle(DSColor.onSurfaceVariant)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(DSColor.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: DS.cornerRadius).stroke(DSColor.outlineVariant.opacity(0.25)))
    }

    private var unitsToggle: some View {
        HStack(spacing: 0) {
            ForEach([DistanceUnit.m, DistanceUnit.yd], id: \.self) { unit in
                Button {
                    Task { await model.changeUnits(unit) }
                } label: {
                    Text(unit == .m ? lm.t.myBag.metersFull : lm.t.myBag.yardsFull)
                        .font(DSFont.labelLG)
                        .frame(maxWidth: .infinity, minHeight: DS.touchTarget)
                }
                .background(model.units == unit ? DSColor.surfaceContainerLowest : .clear)
                .foregroundStyle(model.units == unit ? DSColor.primary : DSColor.onSurfaceVariant)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(4)
        .background(DSColor.surfaceContainer)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

extension ClubCategory: Identifiable {
    public var id: String { rawValue }
}

private struct ClubRowView: View {
    let club: BagClub
    let units: DistanceUnit
    let distanceValue: Int
    let isPutter: Bool
    let onToggle: () -> Void
    let onSetName: (String) -> Void
    let onSetDistance: (String) -> Void

    @Environment(LocaleManager.self) private var lm
    @State private var nameText: String = ""
    @State private var distanceText: String = ""
    @FocusState private var nameFocused: Bool
    @FocusState private var distanceFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(club.customName ?? Clubs.abbrev[club.id] ?? club.id)
                .font(DSFont.labelLG)
                .foregroundStyle(club.enabled ? DSColor.onSurface : DSColor.onSurfaceVariant)
                .frame(width: 56, alignment: .leading)
                .lineLimit(1)
            TextField(club.custom == true ? lm.t.myBag.nameFieldPlaceholderCustom : lm.t.myBag.nameFieldPlaceholderModel, text: $nameText)
                .font(DSFont.labelMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
                .focused($nameFocused)
                .onChange(of: nameFocused) { _, focused in
                    if !focused { onSetName(nameText) }
                }
            if isPutter {
                Text("—")
                    .font(DSFont.labelMD)
                    .foregroundStyle(DSColor.onSurfaceVariant)
                    .frame(width: 56)
            } else {
                HStack(spacing: 2) {
                    TextField("", text: $distanceText)
                        .keyboardType(.numberPad)
                        .font(DSFont.labelLG)
                        .foregroundStyle(DSColor.onSurface)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 44)
                        .focused($distanceFocused)
                        .onChange(of: distanceFocused) { _, focused in
                            if !focused { onSetDistance(distanceText) }
                        }
                        .accessibilityLabel(lm.t.myBag.distanceAria(
                            club.customName ?? club.id, units == .yd ? lm.t.myBag.yardsWord : lm.t.myBag.metersWord
                        ))
                    Text(units == .yd ? lm.t.common.yardsShort : lm.t.common.metersShort)
                        .font(DSFont.labelMD)
                        .foregroundStyle(DSColor.onSurfaceVariant)
                }
                .padding(.horizontal, 6)
                .frame(minHeight: 36)
                .background(DSColor.surfaceContainer)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Button(action: onToggle) {
                Image(systemName: club.enabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(club.enabled ? DSColor.primary : DSColor.outlineVariant)
                    .frame(minWidth: DS.touchTarget, minHeight: DS.touchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lm.t.myBag.enableAria(club.customName ?? club.id))
        }
        .onAppear {
            nameText = club.customName ?? ""
            distanceText = String(distanceValue)
        }
        .onChange(of: distanceValue) { _, value in
            if !distanceFocused { distanceText = String(value) }
        }
    }
}

private struct AddClubSheet: View {
    let category: ClubCategory
    let units: DistanceUnit
    let onAdd: (String, Int) -> Void
    let onCancel: () -> Void

    @Environment(LocaleManager.self) private var lm
    @State private var name = ""
    @State private var distanceText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(lm.t.myBag.newClubTitle(Clubs.categoryLabel(category)))
                .font(DSFont.titleLG)
                .foregroundStyle(DSColor.onSurface)
            TextField(lm.t.myBag.newClubNamePlaceholder, text: $name)
                .font(DSFont.bodyMD)
                .padding(14)
                .background(DSColor.surfaceContainerLow)
                .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
            TextField(units == .yd ? lm.t.myBag.distanceYardsPlaceholder : lm.t.myBag.distanceMetersPlaceholder, text: $distanceText)
                .keyboardType(.numberPad)
                .font(DSFont.bodyMD)
                .padding(14)
                .background(DSColor.surfaceContainerLow)
                .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
            HStack(spacing: 8) {
                DSButton(title: lm.t.common.cancel, style: .secondary, action: onCancel)
                DSButton(title: lm.t.myBag.add,
                         disabled: name.trimmingCharacters(in: .whitespaces).isEmpty || Int(distanceText) == nil) {
                    if let distance = Int(distanceText) {
                        onAdd(name, distance)
                    }
                }
            }
        }
        .padding(20)
        .presentationDetents([.medium])
    }
}
