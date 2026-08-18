// ios/SmartGolfCaddy/ViewModels/JoinGameViewModel.swift
// Порт JoinGame.tsx: вход в лобби по 6-значному коду (ручной ввод или
// автовход по deep-link). `joiner` инжектируется — тесты подменяют сеть.
import Foundation
import Observation

@Observable
@MainActor
final class JoinGameViewModel {
    var code = ""
    var loading = false
    var errorMessage: String?

    /// Инжектируемый вход по коду (тесты подменяют сеть).
    private let joiner: (String, PlayerInfo) async throws -> String?
    private var attemptedCode: String?

    convenience init() {
        self.init(joiner: { code, info in
            try await RoundsService.joinByCode(code, playerInfo: info)
        })
    }

    init(joiner: @escaping (String, PlayerInfo) async throws -> String?) {
        self.joiner = joiner
    }

    var canSubmit: Bool { code.count == 6 && !loading }

    func setCode(_ raw: String) {
        code = Rounds.normalizeLobbyCode(raw)
        if errorMessage != nil { errorMessage = nil }
    }

    func join(profile: AppUser?) async -> String? {
        guard code.count == 6 else {
            errorMessage = "Код должен содержать 6 символов"
            return nil
        }
        loading = true
        errorMessage = nil
        defer { loading = false }
        let info = PlayerInfo(
            name: profile?.name ?? "Голфер",
            avatar: profile?.avatar ?? "",
            totalScore: 0, scoreDiff: 0, email: nil
        )
        do {
            guard let roundId = try await joiner(code, info) else {
                errorMessage = "Лобби с таким кодом не найдено. Проверьте код или попросите хоста создать новое."
                return nil
            }
            return roundId
        } catch {
            errorMessage = "Не удалось присоединиться. Проверьте интернет и попробуйте снова."
            return nil
        }
    }

    /// Автовход по коду из deep-link — ровно один раз на код.
    func autoJoinIfNeeded(initial: String?, profile: AppUser?) async -> String? {
        guard let initial else { return nil }
        let normalized = Rounds.normalizeLobbyCode(initial)
        guard normalized.count == 6, attemptedCode != normalized else { return nil }
        attemptedCode = normalized
        code = normalized
        return await join(profile: profile)
    }
}
