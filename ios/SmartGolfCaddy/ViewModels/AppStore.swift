// ios/SmartGolfCaddy/ViewModels/AppStore.swift
// Зеркало useAppStore веба: единственное поле — клюшка по умолчанию для
// следующей лунки. Живёт в памяти процесса, Firestore не трогает.
import Foundation
import Observation

@Observable
@MainActor
final class AppStore {
    var lastClubUsed: String = "Driver"

    /// Поле, выбранное в поиске — потребляется RoundSetup и очищается им.
    var selectedCourse: CourseResult?
    /// Префилл названия при «Использовать „текст“» из поиска.
    var prefillCourseName: String?
}
