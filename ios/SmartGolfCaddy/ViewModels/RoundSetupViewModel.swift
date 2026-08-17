import Foundation
import Observation

@Observable
@MainActor
final class RoundSetupViewModel {
    var courseName: String = ""
    var totalHoles: Int = 18          // 9 | 18
    var tee: TeeColor = .men
    var creating = false
    var errorMessage: String?

    var effectiveName: String {
        let trimmed = courseName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Поле для гольфа" : trimmed
    }

    /// Создаёт соло-раунд, возвращает id или nil при ошибке (сообщение уже выставлено).
    func createRound(profile: AppUser?) async -> String? {
        guard !creating, let uid = AuthService.currentUserId else { return nil }
        creating = true
        errorMessage = nil
        defer { creating = false }
        let info = PlayerInfo(
            name: profile?.name ?? "Голфер",
            avatar: profile?.avatar ?? "",
            totalScore: 0, scoreDiff: 0,
            email: nil
        )
        do {
            return try await RoundsService.createSoloRound(
                hostId: uid,
                hostInfo: info,
                courseId: "custom-\(UUID().uuidString)",
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
