// ios/SmartGolfCaddy/Views/HoleEditorSheet.swift
// Порт HoleEditorDialog: par 3/4/5 кнопками, дистанция 50–700 м.
import SwiftUI

struct HoleEditorSheet: View {
    let holeNumber: Int
    let currentPar: Int
    let currentDistance: Int
    let saving: Bool
    let onSave: (_ par: Int?, _ distanceMeters: Int?) -> Void
    let onCancel: () -> Void

    @State private var par: Int
    @State private var distanceText: String
    @State private var validationError: String?

    init(holeNumber: Int, currentPar: Int, currentDistance: Int, saving: Bool,
         onSave: @escaping (Int?, Int?) -> Void, onCancel: @escaping () -> Void) {
        self.holeNumber = holeNumber
        self.currentPar = currentPar
        self.currentDistance = currentDistance
        self.saving = saving
        self.onSave = onSave
        self.onCancel = onCancel
        _par = State(initialValue: currentPar)
        _distanceText = State(initialValue: String(currentDistance))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Параметры лунки \(holeNumber)")
                    .font(DSFont.titleLG)
                    .foregroundStyle(DSColor.onSurface)
                Text("Подгоните под реальное поле — изменение видно всем игрокам.")
                    .font(DSFont.labelMD)
                    .foregroundStyle(DSColor.onSurfaceVariant)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("ПАР")
                    .font(DSFont.labelMD)
                    .tracking(1.2)
                    .foregroundStyle(DSColor.onSurfaceVariant)
                HStack(spacing: 8) {
                    ForEach([3, 4, 5], id: \.self) { value in
                        Button {
                            par = value
                        } label: {
                            Text("\(value)")
                                .font(DSFont.displayLG)
                                .frame(maxWidth: .infinity, minHeight: 64)
                        }
                        .background(par == value ? DSColor.primary : DSColor.surfaceContainerLowest)
                        .foregroundStyle(par == value ? DSColor.onPrimary : DSColor.onSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(par == value ? DSColor.primary : DSColor.outlineVariant, lineWidth: 2)
                        )
                        .disabled(saving)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("ДИСТАНЦИЯ, МЕТРОВ")
                    .font(DSFont.labelMD)
                    .tracking(1.2)
                    .foregroundStyle(DSColor.onSurfaceVariant)
                TextField("", text: $distanceText)
                    .keyboardType(.numberPad)
                    .font(DSFont.headlineMD)
                    .monospacedDigit()
                    .padding(14)
                    .background(DSColor.surfaceContainerLow)
                    .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
                    .disabled(saving)
                if let validationError {
                    Text(validationError)
                        .font(DSFont.labelMD)
                        .foregroundStyle(DSColor.error)
                }
            }

            HStack(spacing: 8) {
                DSButton(title: "Отмена", style: .secondary, disabled: saving, action: onCancel)
                DSButton(title: saving ? "Сохраняем..." : "Сохранить", disabled: saving) {
                    submit()
                }
            }
        }
        .padding(20)
        .presentationDetents([.medium])
    }

    private func submit() {
        guard let parsed = Int(distanceText), (50...700).contains(parsed) else {
            validationError = "Дистанция должна быть 50–700 метров"
            return
        }
        validationError = nil
        let parPatch: Int? = par != currentPar ? par : nil
        let distPatch: Int? = parsed != currentDistance ? parsed : nil
        if parPatch == nil && distPatch == nil {
            onCancel()
            return
        }
        onSave(parPatch, distPatch)
    }
}
