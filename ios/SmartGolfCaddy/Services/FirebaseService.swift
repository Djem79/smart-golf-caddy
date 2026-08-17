// ios/SmartGolfCaddy/Services/FirebaseService.swift
// Единственная точка доступа к Firebase-инстансам (зеркало src/firebase.ts).
import FirebaseFirestore
import FirebaseFunctions

enum FirebaseService {
    static var db: Firestore { Firestore.firestore() }

    // Функции живут в us-central1 (Firestore — europe-west3, это ожидаемо).
    static let functions = Functions.functions(region: "us-central1")

    // Рекурсивно заменяет Firestore Timestamp на Date во вложенных
    // словарях/массивах — аналог normalizeRound на границе Services.
    static func normalizedDates(_ value: Any) -> Any {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let dict = value as? [String: Any] { return dict.mapValues(normalizedDates) }
        if let array = value as? [Any] { return array.map(normalizedDates) }
        return value
    }
}
