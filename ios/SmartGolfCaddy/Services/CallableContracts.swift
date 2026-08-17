// ios/SmartGolfCaddy/Services/CallableContracts.swift
// SYNC: зеркало functions/src/contracts.ts (Zod, авторитет) и
// src/types/callable.ts (веб-клиент). При правке схемы на любой
// стороне — обновить все три файла.
import Foundation

struct RecordShotInput: Encodable {
    let roundId: String
    let holeIndex: Int
    let clubs: [String]
    let targetUid: String?
}

struct UpdateHoleConfigInput: Encodable {
    let roundId: String
    let holeIndex: Int
    let par: Int?
    let distanceMeters: Int?
}

struct JoinLobbyInput: Encodable {
    let code: String
}

struct ShareInput: Encodable {
    let roundId: String
    let toEmail: String
}

// Encodable → [String: Any] для Functions SDK (nil-поля выпадают сами).
func callableDict<T: Encodable>(_ value: T) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    let object = try JSONSerialization.jsonObject(with: data)
    return object as? [String: Any] ?? [:]
}
