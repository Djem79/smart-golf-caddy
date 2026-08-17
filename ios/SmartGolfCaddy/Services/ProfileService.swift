// ios/SmartGolfCaddy/Services/ProfileService.swift
// Подписка на профиль. onError ОБЯЗАТЕЛЕН у вызывающего — иначе ошибка
// прав/сети превращается в вечный спиннер (правило из веб-версии).
import FirebaseFirestore

enum ProfileService {
    static func subscribeToProfile(
        uid: String,
        onChange: @escaping (AppUser?) -> Void,
        onError: @escaping (Error) -> Void
    ) -> () -> Void {
        let listener = FirebaseService.db.collection("users").document(uid)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onError(error)
                    return
                }
                guard let snapshot, snapshot.exists, let raw = snapshot.data() else {
                    onChange(nil)
                    return
                }
                let data = FirebaseService.normalizedDates(raw) as? [String: Any] ?? raw
                onChange(AppUser(uid: snapshot.documentID, data: data))
            }
        return { listener.remove() }
    }
}
