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

    /// Код лобби: только буквы/цифры алфавита LOBBY_CHARS, верхний регистр, 6 символов.
    static func normalizeLobbyCode(_ raw: String) -> String {
        let allowed = Set(lobbyChars)
        let cleaned = raw.uppercased().filter { allowed.contains($0) }
        return String(cleaned.prefix(6))
    }

    /// Payload группового раунда — вынесен из сервиса, чтобы форму документа
    /// можно было проверить тестом без Firestore.
    static func groupRoundPayload(
        hostId: String, hostInfo: PlayerInfo,
        courseId: String, courseName: String,
        totalHoles: Int, tee: TeeColor, playMode: PlayMode
    ) -> [String: Any] {
        [
            "courseId": courseId,
            "courseName": courseName,
            "totalHoles": totalHoles,
            "lobbyCode": generateLobbyCode(),
            "status": "lobby",
            "hostId": hostId,
            "players": [hostId: hostInfo.firestoreData],
            "playerIds": [hostId],
            "tee": tee.rawValue,
            "playMode": playMode.rawValue,
            "holes": buildDefaultHoles(totalHoles: totalHoles, tee: tee).map { $0.firestoreData },
            "startedAt": NSNull(),
            "finishedAt": NSNull(),
        ]
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

    /// Групповой раунд создаётся в статусе lobby: игроки входят по коду, хост
    /// стартует. createdAt добавляется здесь (serverTimestamp нельзя положить
    /// в чистый payload-хелпер).
    static func createGroupRound(
        hostId: String, hostInfo: PlayerInfo,
        courseId: String, courseName: String,
        totalHoles: Int, tee: TeeColor, playMode: PlayMode
    ) async throws -> String {
        let ref = FirebaseService.db.collection("rounds").document()
        var payload = Rounds.groupRoundPayload(
            hostId: hostId, hostInfo: hostInfo,
            courseId: courseId, courseName: courseName,
            totalHoles: totalHoles, tee: tee, playMode: playMode
        )
        payload["createdAt"] = FieldValue.serverTimestamp()
        try await ref.setData(payload)
        return ref.documentID
    }

    /// Вход по коду — ТОЛЬКО через callable (Admin SDK): правила запрещают
    /// клиенту писать `players`. nil = лобби с таким кодом не найдено.
    static func joinByCode(_ code: String, playerInfo: PlayerInfo) async throws -> String? {
        let payload = try callableDict(JoinLobbyInput(
            code: Rounds.normalizeLobbyCode(code),
            playerInfo: JoinLobbyPlayerInfo(
                name: playerInfo.name,
                avatar: playerInfo.avatar,
                email: nil,          // сервер подставит email из токена
                totalScore: 0,
                scoreDiff: 0
            )
        ))
        let result = try await FirebaseService.functions.httpsCallable("joinLobbyByCode").call(payload)
        guard let data = result.data as? [String: Any] else { return nil }
        return data["roundId"] as? String
    }

    static func startRound(roundId: String) async throws {
        try await FirebaseService.db.collection("rounds").document(roundId).updateData([
            "status": "active",
            "startedAt": FieldValue.serverTimestamp(),
        ])
    }

    /// Выход из лобби. Правила требуют, чтобы новый playerIds был РОВНО
    /// старым минус свой uid, поэтому передаём актуальный список из подписки
    /// (FieldValue.arrayRemove не даёт правилам доказать равенство множеств).
    static func leaveLobby(roundId: String, userId: String, currentPlayerIds: [String]) async throws {
        let next = currentPlayerIds.filter { $0 != userId }
        try await FirebaseService.db.collection("rounds").document(roundId).updateData([
            "playerIds": next,
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
                if let round = Round(id: snapshot.documentID, data: data) {
                    onChange(round)
                } else {
                    onError(NSError(
                        domain: "SmartGolfCaddy", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: AppLocaleStore.strings.roundsService.corruptedRoundData]
                    ))
                }
            }
        return { listener.remove() }
    }

    /// Разовое (не подписка) чтение раунда. Нужно WatchBridge при приёме
    /// батча ударов с часов: чтобы дописать unsyncedShots-хвост к уже
    /// известным телефону клюшкам лунки, а не затереть их (критический
    /// инвариант — см. комментарий в WatchBridge.swift). nil, если раунд не
    /// найден.
    ///
    /// source: .server — ПРИНУДИТЕЛЬНО живой запрос к серверу, НЕ .default.
    /// Живое ревью Task 4 (Fix 1) указало: .default при офлайне молча
    /// подставляет локальный Firestore-кэш, а этот кэш не знает о
    /// собственных офлайн-записях ТЕЛЕФОНА (они идут через Cloud
    /// Function recordShot, а не прямой клиентский write — оптимистичного
    /// обновления кэша для них нет); мердж на такой устаревшей базе мог
    /// затереть недавно записанный на телефоне удар. При офлайне/
    /// недоступности сервера .server ЗАКОНОМЕРНО бросает — вызывающая
    /// сторона (WatchBridge.applyBatch) уже трактует throw как "писать
    /// нельзя, часы повторят" (тот же критический инвариант). nil, если
    /// раунд не найден.
    static func getRound(roundId: String) async throws -> Round? {
        let snapshot = try await FirebaseService.db.collection("rounds").document(roundId).getDocument(source: .server)
        guard snapshot.exists, let raw = snapshot.data() else { return nil }
        let data = FirebaseService.normalizedDates(raw) as? [String: Any] ?? raw
        return Round(id: snapshot.documentID, data: data)
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

    // distances: [Int]? — nil (не «[]») означает «не передавать поле».
    // Сервер (Zod-refine в contracts.ts) требует distances.length == clubs.length,
    // КОГДА distances присутствует; пустой массив при непустых clubs — invalid-argument.
    // nil → JSONEncoder дропает ключ → сервер сохраняет прежние distances.
    static func recordShot(roundId: String, holeIndex: Int, targetUid: String, clubs: [String], distances: [Int]?) async throws {
        let payload = try callableDict(RecordShotInput(
            roundId: roundId, holeIndex: holeIndex, clubs: clubs, distances: distances, targetUid: targetUid
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
