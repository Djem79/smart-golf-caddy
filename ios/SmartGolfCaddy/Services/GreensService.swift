// ios/SmartGolfCaddy/Services/GreensService.swift
// Чтение/запись краудсорс-меток гринов. Пишем ТОЛЬКО свой документ
// (правила запрещают чужие), читаем все — усреднение на клиенте.
import FirebaseFirestore

enum GreensService {
    static func subscribeToMarks(
        courseKey: String,
        onChange: @escaping ([GreenMarkSet]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> () -> Void {
        let listener = FirebaseService.db
            .collection("courses").document(courseKey)
            .collection("greenMarks")
            .addSnapshotListener { snapshot, error in
                if let error { onError(error); return }
                let sets = (snapshot?.documents ?? []).compactMap { GreenMarkSet(data: $0.data()) }
                onChange(sets)
            }
        return { listener.remove() }
    }

    /// Merge по конкретной лунке: точечный путь `holes.<N>` не трогает
    /// остальные лунки в документе игрока.
    static func saveMark(courseKey: String, userId: String, hole: Int, lat: Double, lng: Double) async throws {
        try await FirebaseService.db
            .collection("courses").document(courseKey)
            .collection("greenMarks").document(userId)
            .setData([
                "holes": [String(hole): ["lat": lat, "lng": lng]],
                "updatedAt": FieldValue.serverTimestamp(),
            ], merge: true)
    }
}
