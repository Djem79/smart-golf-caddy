// ios/SmartGolfCaddy/Services/RoundsService.swift
// Порт src/services/rounds.ts (соло-части + чистые хелперы).
// Колбэки подписок доставляются на main (гарантия Firebase) — VM вправе
// мутировать состояние без hop. onError ОБЯЗАТЕЛЕН у вызывающего.
import FirebaseFirestore
import Foundation

// Чистые хелперы — отдельный namespace, тестируются без Firebase.
enum Rounds {
    static let lobbyChars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")  // без 0/O/1/I

    static func defaultHolePars(totalHoles: Int) -> [Int] {
        if totalHoles == 9 { return [4, 3, 5, 4, 4, 3, 5, 4, 4] }
        return [4, 4, 3, 5, 4, 3, 4, 5, 4, 4, 3, 5, 4, 4, 3, 5, 4, 4]
    }

    static func buildDefaultHoles(totalHoles: Int, tee: TeeColor = .men) -> [HoleConfig] {
        let mult = tee.multiplier
        return defaultHolePars(totalHoles: totalHoles).enumerated().map { i, par in
            let base = par == 3 ? 150 : (par == 5 ? 480 : 360)
            return HoleConfig(data: [
                "holeNumber": i + 1, "par": par,
                "distanceMeters": Int((Double(base) * mult).rounded()),
                "shots": [String: Any](),
            ])!
        }
    }

    static func generateLobbyCode() -> String {
        String((0..<6).map { _ in lobbyChars.randomElement()! })
    }
}

enum RoundsService {

    /// Соло-раунд: сразу active, playMode stroke (веб-паритет createRound(mode: 'solo')).
    static func createSoloRound(
        hostId: String,
        hostInfo: PlayerInfo,
        courseId: String,
        courseName: String,
        totalHoles: Int,
        tee: TeeColor
    ) async throws -> String {
        let ref = FirebaseService.db.collection("rounds").document()
        try await ref.setData([
            "courseId": courseId,
            "courseName": courseName,
            "totalHoles": totalHoles,
            "lobbyCode": Rounds.generateLobbyCode(),
            "status": "active",
            "hostId": hostId,
            "players": [hostId: hostInfo.firestoreData],
            "playerIds": [hostId],
            "tee": tee.rawValue,
            "playMode": "stroke",
            "holes": Rounds.buildDefaultHoles(totalHoles: totalHoles, tee: tee).map { $0.firestoreData },
            "startedAt": FieldValue.serverTimestamp(),
            "finishedAt": NSNull(),
            "createdAt": FieldValue.serverTimestamp(),
        ])
        return ref.documentID
    }

    static func finishRound(roundId: String) async throws {
        try await FirebaseService.db.collection("rounds").document(roundId).updateData([
            "status": "finished",
            "finishedAt": FieldValue.serverTimestamp(),
        ])
    }

    static func subscribeToRound(
        roundId: String,
        onChange: @escaping (Round) -> Void,
        onError: @escaping (Error) -> Void
    ) -> () -> Void {
        let listener = FirebaseService.db.collection("rounds").document(roundId)
            .addSnapshotListener { snapshot, error in
                if let error { onError(error); return }
                guard let snapshot, snapshot.exists, let raw = snapshot.data() else { return }
                let data = FirebaseService.normalizedDates(raw) as? [String: Any] ?? raw
                if let round = Round(id: snapshot.documentID, data: data) { onChange(round) }
            }
        return { listener.remove() }
    }

    static func getUserRounds(userId: String, limitTo: Int = 50) async throws -> [Round] {
        let snapshot = try await FirebaseService.db.collection("rounds")
            .whereField("playerIds", arrayContains: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: limitTo)
            .getDocuments()
        return snapshot.documents.compactMap { doc in
            let data = FirebaseService.normalizedDates(doc.data()) as? [String: Any] ?? doc.data()
            return Round(id: doc.documentID, data: data)
        }
    }

    static func recordShot(roundId: String, holeIndex: Int, targetUid: String, clubs: [String]) async throws {
        let payload = try callableDict(RecordShotInput(
            roundId: roundId, holeIndex: holeIndex, clubs: clubs, targetUid: targetUid
        ))
        _ = try await FirebaseService.functions.httpsCallable("recordShot").call(payload)
    }

    static func updateHoleConfig(roundId: String, holeIndex: Int, par: Int?, distanceMeters: Int?) async throws {
        let payload = try callableDict(UpdateHoleConfigInput(
            roundId: roundId, holeIndex: holeIndex, par: par, distanceMeters: distanceMeters
        ))
        _ = try await FirebaseService.functions.httpsCallable("updateHoleConfig").call(payload)
    }
}
