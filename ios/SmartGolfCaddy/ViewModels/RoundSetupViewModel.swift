import Foundation
import Observation

enum RoundMode: String, CaseIterable {
    case solo, group
}

@Observable
@MainActor
final class RoundSetupViewModel {
    var courseName: String = ""
    var totalHoles: Int = 18          // 9 | 18
    var tee: TeeColor = .men
    var mode: RoundMode = .solo
    var playMode: PlayMode = .stroke
    var creating = false
    var errorMessage: String?
    var selectedPlaceId: String?
    var selectedVicinity: String = ""
    var selectedDistanceKm: Double = 0

    var effectiveName: String {
        let trimmed = courseName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Поле для гольфа" : trimmed
    }

    /// Забирает выбранное поле/префилл из стора (одноразово) и чистит стор.
    func adopt(store: AppStore) {
        if let course = store.selectedCourse {
            courseName = course.name
            selectedPlaceId = course.placeId
            selectedVicinity = course.vicinity
            selectedDistanceKm = course.distanceKm
        } else if let prefill = store.prefillCourseName {
            courseName = prefill
        }
        store.selectedCourse = nil
        store.prefillCourseName = nil
    }

    /// Создаёт соло-раунд, возвращает id или nil при ошибке (сообщение уже выставлено).
    func createRound(profile: AppUser?) async -> String? {
        guard !creating, let uid = AuthService.currentUserId else { return nil }
        creating = true
        errorMessage = nil
        defer { creating = false }
        // Паритет с вебом: user.email ?? '' (пустую строку не шлём — nil
        // опускается в firestoreData, сервер имеет Auth-lookup fallback).
        let info = PlayerInfo(
            name: profile?.name ?? "Голфер",
            avatar: profile?.avatar ?? "",
            totalScore: 0, scoreDiff: 0,
            email: AuthService.currentUserEmail
        )
        // Match play осмыслен только вдвоём — соло-раунд всегда stroke
        // (веб-паритет createRound).
        let effectivePlayMode: PlayMode = mode == .group ? playMode : .stroke
        do {
            if mode == .group {
                return try await RoundsService.createGroupRound(
                    hostId: uid, hostInfo: info,
                    courseId: selectedPlaceId ?? "custom-\(UUID().uuidString)",
                    courseName: effectiveName,
                    totalHoles: totalHoles, tee: tee, playMode: effectivePlayMode
                )
            }
            return try await RoundsService.createSoloRound(
                hostId: uid,
                hostInfo: info,
                courseId: selectedPlaceId ?? "custom-\(UUID().uuidString)",
                courseName: effectiveName,
                totalHoles: totalHoles,
                tee: tee
            )
        } catch {
            errorMessage = "Не удалось создать раунд. Попробуйте ещё раз."
            return nil
        }
    }
}
