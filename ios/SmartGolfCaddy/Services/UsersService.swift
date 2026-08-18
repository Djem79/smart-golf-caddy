// ios/SmartGolfCaddy/Services/UsersService.swift
// Порт src/services/users.ts (записи профиля; подписка уже в ProfileService).
import FirebaseFirestore

enum UsersService {
    static func updateBag(uid: String, bag: [BagClub]) async throws {
        try await FirebaseService.db.collection("users").document(uid)
            .setData(["bag": bag.map { $0.firestoreData }], merge: true)
    }

    static func updateUnits(uid: String, units: DistanceUnit) async throws {
        try await FirebaseService.db.collection("users").document(uid)
            .setData(["units": units.rawValue], merge: true)
    }
}
