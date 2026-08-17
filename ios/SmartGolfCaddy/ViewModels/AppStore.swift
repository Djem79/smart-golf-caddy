// ios/SmartGolfCaddy/ViewModels/AppStore.swift
// Зеркало useAppStore веба: единственное поле — клюшка по умолчанию для
// следующей лунки. Живёт в памяти процесса, Firestore не трогает.
import Foundation
import Observation

@Observable
@MainActor
final class AppStore {
    var lastClubUsed: String = "Driver"
}
