# iOS Phase 2a — Solo Round Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Играбельный соло-раунд конец-в-конец на iOS: Home («Продолжить раунд», последние раунды) → Настройка раунда → Трекер лунок (удары, клюшки, оптимистичный UI, офлайн-очередь) → Итоги. Полный поведенческий паритет с веб-версией.

**Architecture:** Те же слои, что в Фазе 1: Views → ViewModels (@Observable) → Services → Firebase SDK; Models — чистые структуры. Новое: NavigationStack-роутер (@Observable AppRouter), сервис раундов (Firestore + callable), офлайн-очередь ударов (файл в Application Support + NWPathMonitor), порт скоринга.

**Tech Stack:** Swift/SwiftUI (iOS 17), FirebaseFirestore/FirebaseFunctions, Network.framework (NWPathMonitor).

**Spec:** `docs/superpowers/specs/2026-08-17-ios-app-design.md`. Веб-исходники — source of truth поведения: `src/services/rounds.ts`, `src/services/scoring.ts`, `src/services/shotQueue.ts`, `src/screens/{Home,RoundSetup,HoleTracker,RoundResults}.tsx`.

## Global Constraints

- Сборка/тесты ТОЛЬКО через `./ios/scripts/test.sh` и `./ios/scripts/build.sh` (из корня репо). Прямой xcodebuild запрещён. «Стандартная тест-команда» в шагах = `./ios/scripts/test.sh`.
- FirebaseFirestore линкуется ТОЛЬКО в app-таргет (#14464): НИКОГДА не добавлять Firebase-пакеты в тест-таргет и не включать `FIREBASE_SOURCE_FIRESTORE`. Тестам классы Firebase доступны из рантайма хоста (`NSClassFromString`).
- `import Firebase*` в прод-коде — только `Services/*.swift` (+ AppDelegate, DEBUG-only DiagnosticsView); `import GoogleSignIn` — только Services/ + RootView.onOpenURL. Тестовым файлам импорт Firebase ЗАПРЕЩЁН (см. выше — не линкуется).
- **Конвенция конкурентности (новая, обязательная):** все колбэки сервисов (onChange/onError подписок) вызываются на main thread — Firebase доставляет листенеры на main. Каждый сервисный колбэк-параметр помечается `@MainActor @Sendable` в сигнатуре замыкания НЕ нужно — вместо этого ViewModel-замыкания уже исполняются на main; фиксируем инвариант комментарием в каждом сервисе: «Колбэки доставляются на main (гарантия Firebase); VM вправе мутировать состояние без hop».
- **Каждая per-screen ViewModel обязана**: (а) принимать onError у каждой подписки и показывать ошибку + escape-действие в UI (правило веба); (б) снимать подписки в `deinit` (образец — SessionViewModel c `@MainActor deinit`).
- **Dynamic Type: решение зафиксировано — фиксированные размеры шрифтов** (паритет с вебом, который не масштабирует). Не добавлять `relativeTo:`.
- Русский UI дословно из этого плана. Никаких эмодзи — только SF Symbols. Touch targets ≥ 48 pt (`DS.touchTarget`).
- `par` в UI ограничен значениями 3/4/5 (кнопки, не свободный ввод).
- DEBUG-диагностика (DiagnosticsView) жжёт квоту join (30/день/uid) — в смоуках не нажимать многократно.
- Коммит после каждой задачи. Не коммитить секреты (GoogleService-Info.plist, Local.xcconfig).
- Интерфейсы Фазы 1, доступные всем задачам: `Round(id:data:)`, `HoleConfig`, `HoleShots.resolvedClubs`, `PlayerInfo`, `TeeColor.multiplier`, `Clubs.*`, `AppUser.resolvedBag`, `Score.*`, `pluralRu`, `FirebaseService.db/.functions/.normalizedDates`, `callableDict(_:)`, `RecordShotInput/UpdateHoleConfigInput`, `AuthService.currentUserId`, `ProfileService.subscribeToProfile`, `SessionViewModel` (`.profile`, `.state`), `DSColor/DSFont/DS`.

---

### Task 1: Порт скоринга + TEE_LABELS (TDD)

**Files:**
- Create: `ios/SmartGolfCaddy/Models/Scoring.swift`
- Modify: `ios/SmartGolfCaddy/Models/Round.swift` (extension TeeColor — метки тии)
- Test: `ios/SmartGolfCaddyTests/ScoringTests.swift`

**Interfaces:**
- Consumes: `Round`, `HoleShots.resolvedClubs` (Фаза 1).
- Produces (дословно для Tasks 4–7):
  - `struct PlayerTotals { var totalScore: Int; var scoreDiff: Int }`; `Scoring.playerTotals(round:userId:) -> PlayerTotals`
  - `struct ClubStat { let club: String; let count: Int; let percent: Int }`; `Scoring.clubUsage(rounds:userId:) -> [ClubStat]` (и перегрузка `clubUsage(round:userId:)`)
  - `struct LeaderboardEntry { uid, name, avatar, totalScore, scoreDiff, thru }`; `Scoring.leaderboard(round:) -> [LeaderboardEntry]`
  - `struct HoleResultStats { eagle, birdie, par, bogey, double, worse: Int }`; `struct PlayerStats { roundsPlayed, totalShots: Int; avgShots: Double; bestScore, bestScoreDiff: Int?; holeStats: HoleResultStats; totalHolesPlayed: Int }`; `Scoring.playerStats(rounds:userId:) -> PlayerStats`
  - `struct HandicapResult { index: Double; basedOnRounds: Int; bestUsed: Int }`; `Scoring.handicap(rounds:userId:) -> HandicapResult?`
  - `struct MatchPlayStatus { leaderUid, trailerUid: String?; holesPlayed, holesRemaining, delta: Int; label: String; closed: Bool }`; `Scoring.matchPlayStatus(round:uidA:uidB:) -> MatchPlayStatus`
  - `extension TeeColor { var label: String; var teeDescription: String; var bgHex: String; var textHex: String }`

- [ ] **Step 1: Написать падающие тесты**

```swift
// ios/SmartGolfCaddyTests/ScoringTests.swift
import XCTest
@testable import SmartGolfCaddy

// Фикстуры строим через Round(id:data:) — тот же путь, что у прод-декода.
private func makeRound(
    holes: [[String: Any]],
    players: [String: [String: Any]] = ["u1": ["name": "А", "avatar": "", "totalScore": 0, "scoreDiff": 0]],
    playerIds: [String] = ["u1"],
    status: String = "active",
    playMode: String? = nil
) -> Round {
    var data: [String: Any] = [
        "courseId": "c", "courseName": "Поле", "totalHoles": holes.count,
        "lobbyCode": "ABC234", "status": status, "hostId": "u1",
        "players": players, "playerIds": playerIds,
        "holes": holes, "createdAt": Date(),
    ]
    if let playMode { data["playMode"] = playMode }
    return Round(id: "r", data: data)!
}

private func hole(_ n: Int, par: Int, shots: [String: [String: Any]] = [:]) -> [String: Any] {
    ["holeNumber": n, "par": par, "distanceMeters": 360, "shots": shots]
}

final class ScoringTests: XCTestCase {

    // MARK: playerTotals — считаются только лунки с ударами

    func testPlayerTotalsCountsOnlyPlayedHoles() {
        let round = makeRound(holes: [
            hole(1, par: 4, shots: ["u1": ["count": 5, "clubs": ["Driver", "7i", "7i", "PW", "Putter"]]]),
            hole(2, par: 3, shots: ["u1": ["count": 2, "clubs": ["7i", "Putter"]]]),
            hole(3, par: 5, shots: [:]),   // не сыграна — не входит ни в счёт, ни в пар
        ])
        let totals = Scoring.playerTotals(round: round, userId: "u1")
        XCTAssertEqual(totals.totalScore, 7)
        XCTAssertEqual(totals.scoreDiff, 0)   // 7 − (4+3)
    }

    func testPlayerTotalsEmpty() {
        let round = makeRound(holes: [hole(1, par: 4)])
        let totals = Scoring.playerTotals(round: round, userId: "u1")
        XCTAssertEqual(totals.totalScore, 0)
        XCTAssertEqual(totals.scoreDiff, 0)
    }

    // MARK: clubUsage — сортировка по убыванию, «Неизвестно» исключён

    func testClubUsage() {
        let round = makeRound(holes: [
            hole(1, par: 4, shots: ["u1": ["count": 3, "clubs": ["Driver", "7i", "7i"]]]),
            hole(2, par: 4, shots: ["u1": ["count": 2, "clubs": [], "club": ""]]),  // resolvedClubs → «Неизвестно» ×2
        ])
        let usage = Scoring.clubUsage(round: round, userId: "u1")
        XCTAssertEqual(usage.map(\.club), ["7i", "Driver"])
        XCTAssertEqual(usage[0].count, 2)
        XCTAssertEqual(usage[0].percent, 67)  // round(2/3×100)
        XCTAssertEqual(usage[1].percent, 33)
    }

    func testClubUsageTieBreaksByName() {
        let round = makeRound(holes: [
            hole(1, par: 4, shots: ["u1": ["count": 2, "clubs": ["SW", "Driver"]]]),
        ])
        let usage = Scoring.clubUsage(round: round, userId: "u1")
        XCTAssertEqual(usage.map(\.club), ["Driver", "SW"])  // count равен → по имени
    }

    // MARK: leaderboard — без ударов тонут вниз, сортировка diff→total→имя

    func testLeaderboardSort() {
        let round = makeRound(
            holes: [
                hole(1, par: 4, shots: [
                    "a": ["count": 4, "clubs": ["Driver", "7i", "PW", "Putter"]],
                    "b": ["count": 3, "clubs": ["Driver", "PW", "Putter"]],
                ]),
            ],
            players: [
                "a": ["name": "Аня", "avatar": "", "totalScore": 0, "scoreDiff": 0],
                "b": ["name": "Борис", "avatar": "", "totalScore": 0, "scoreDiff": 0],
                "c": ["name": "Вера", "avatar": "", "totalScore": 0, "scoreDiff": 0],
            ],
            playerIds: ["a", "b", "c"]
        )
        let lb = Scoring.leaderboard(round: round)
        XCTAssertEqual(lb.map(\.uid), ["b", "a", "c"])  // c без ударов — внизу
        XCTAssertEqual(lb[0].thru, 1)
        XCTAssertEqual(lb[2].thru, 0)
    }

    // MARK: playerStats

    func testPlayerStats() {
        let r1 = makeRound(holes: [
            hole(1, par: 4, shots: ["u1": ["count": 3, "clubs": ["Driver", "PW", "Putter"]]]),  // birdie
            hole(2, par: 4, shots: ["u1": ["count": 6, "clubs": ["Driver", "7i", "7i", "PW", "Putter", "Putter"]]]),  // double
        ])
        let r2 = makeRound(holes: [
            hole(1, par: 4, shots: ["u1": ["count": 4, "clubs": ["Driver", "7i", "PW", "Putter"]]]),  // par
        ])
        let r3 = makeRound(holes: [hole(1, par: 4)])  // не играл — не считается
        let stats = Scoring.playerStats(rounds: [r1, r2, r3], userId: "u1")
        XCTAssertEqual(stats.roundsPlayed, 2)
        XCTAssertEqual(stats.totalShots, 13)
        XCTAssertEqual(stats.avgShots, 6.5)
        XCTAssertEqual(stats.bestScore, 4)
        XCTAssertEqual(stats.bestScoreDiff, 0)  // r2: 4−4=0 лучше, чем r1: 9−8=1
        XCTAssertEqual(stats.holeStats.birdie, 1)
        XCTAssertEqual(stats.holeStats.double, 1)
        XCTAssertEqual(stats.holeStats.par, 1)
        XCTAssertEqual(stats.totalHolesPlayed, 3)
    }

    // MARK: handicap — null при <3 раундов; best 8 из 20 × 0.96

    func testHandicapNeedsThreeRounds() {
        let r = makeRound(holes: [hole(1, par: 4, shots: ["u1": ["count": 5, "clubs": ["Driver", "7i", "7i", "PW", "Putter"]]])], status: "finished")
        XCTAssertNil(Scoring.handicap(rounds: [r, r], userId: "u1"))
    }

    func testHandicapAveragesBest() {
        // Три finished-раунда c diff: +1, +1, +4 → best 3 = все, avg=2.0, ×0.96=1.92 → 1.9
        func finished(diffOverPar: Int) -> Round {
            makeRound(holes: [hole(1, par: 4, shots: ["u1": ["count": 4 + diffOverPar, "clubs": Array(repeating: "7i", count: 4 + diffOverPar)]])], status: "finished")
        }
        let result = Scoring.handicap(rounds: [finished(diffOverPar: 1), finished(diffOverPar: 1), finished(diffOverPar: 4)], userId: "u1")
        XCTAssertEqual(result?.index, 1.9)
        XCTAssertEqual(result?.basedOnRounds, 3)
        XCTAssertEqual(result?.bestUsed, 3)
    }

    func testHandicapIgnoresUnfinished() {
        let active = makeRound(holes: [hole(1, par: 4, shots: ["u1": ["count": 5, "clubs": ["7i"]]])], status: "active")
        XCTAssertNil(Scoring.handicap(rounds: [active, active, active], userId: "u1"))
    }

    // MARK: match play

    func testMatchPlayLabels() {
        // 3 лунки: a выигрывает 1-ю и 2-ю, 3-я не сыграна → 2&1 (closed)
        let round = makeRound(
            holes: [
                hole(1, par: 4, shots: ["a": ["count": 3, "clubs": ["7i", "PW", "Putter"]], "b": ["count": 4, "clubs": ["7i", "7i", "PW", "Putter"]]]),
                hole(2, par: 4, shots: ["a": ["count": 3, "clubs": ["7i", "PW", "Putter"]], "b": ["count": 5, "clubs": ["7i", "7i", "7i", "PW", "Putter"]]]),
                hole(3, par: 4),
            ],
            players: [
                "a": ["name": "Аня", "avatar": "", "totalScore": 0, "scoreDiff": 0],
                "b": ["name": "Борис", "avatar": "", "totalScore": 0, "scoreDiff": 0],
            ],
            playerIds: ["a", "b"], playMode: "match"
        )
        let st = Scoring.matchPlayStatus(round: round, uidA: "a", uidB: "b")
        XCTAssertEqual(st.leaderUid, "a")
        XCTAssertEqual(st.delta, 2)
        XCTAssertEqual(st.holesRemaining, 1)
        XCTAssertTrue(st.closed)
        XCTAssertEqual(st.label, "2&1")
    }

    func testMatchPlayAllSquareAndFinished() {
        let round = makeRound(
            holes: [hole(1, par: 4, shots: ["a": ["count": 4, "clubs": ["7i", "7i", "PW", "Putter"]], "b": ["count": 4, "clubs": ["7i", "7i", "PW", "Putter"]]])],
            players: [
                "a": ["name": "Аня", "avatar": "", "totalScore": 0, "scoreDiff": 0],
                "b": ["name": "Борис", "avatar": "", "totalScore": 0, "scoreDiff": 0],
            ],
            playerIds: ["a", "b"], playMode: "match"
        )
        XCTAssertEqual(Scoring.matchPlayStatus(round: round, uidA: "a", uidB: "b").label, "AS")
    }

    // MARK: TeeColor labels

    func testTeeLabels() {
        XCTAssertEqual(TeeColor.men.label, "Мужские")
        XCTAssertEqual(TeeColor.pro.bgHex, "#0A3010")
        XCTAssertEqual(TeeColor.ladies.textHex, "#FFFFFF")
        XCTAssertEqual(TeeColor.senior.teeDescription, "Чуть ближе · −10%")
    }
}
```

Примечание к testClubUsage: вторая лунка использует legacy-форму `{"count": 2, "clubs": [], "club": ""}` — `resolvedClubs` даёт `["Неизвестно", "Неизвестно"]` (фикс Фазы 1), и «Неизвестно» исключается из статистики.

- [ ] **Step 2: Прогнать — падает компиляцией** (`cannot find 'Scoring'`). Стандартная тест-команда.

- [ ] **Step 3: Реализация**

```swift
// ios/SmartGolfCaddy/Models/Scoring.swift
// Порт src/services/scoring.ts — веб является source of truth.
// Чистые функции, только Foundation.
import Foundation

struct PlayerTotals: Equatable {
    var totalScore: Int
    var scoreDiff: Int
}

struct ClubStat: Equatable, Identifiable {
    let club: String
    let count: Int
    let percent: Int
    var id: String { club }
}

struct LeaderboardEntry: Equatable, Identifiable {
    let uid: String
    let name: String
    let avatar: String
    let totalScore: Int
    let scoreDiff: Int
    let thru: Int
    var id: String { uid }
}

struct HoleResultStats: Equatable {
    var eagle = 0, birdie = 0, par = 0, bogey = 0, double = 0, worse = 0
}

struct PlayerStats: Equatable {
    var roundsPlayed: Int
    var totalShots: Int
    var avgShots: Double
    var bestScore: Int?
    var bestScoreDiff: Int?
    var holeStats: HoleResultStats
    var totalHolesPlayed: Int
}

struct HandicapResult: Equatable {
    var index: Double
    var basedOnRounds: Int
    var bestUsed: Int
}

struct MatchPlayStatus: Equatable {
    var leaderUid: String?
    var trailerUid: String?
    var holesPlayed: Int
    var holesRemaining: Int
    var delta: Int
    var label: String
    var closed: Bool
}

enum Scoring {

    static func playerTotals(round: Round, userId: String) -> PlayerTotals {
        var totalScore = 0
        var totalPar = 0
        var hasAnyShots = false
        for hole in round.holes {
            let count = hole.shots[userId]?.count ?? 0
            if count > 0 {
                hasAnyShots = true
                totalScore += count
                totalPar += hole.par
            }
        }
        if !hasAnyShots { return PlayerTotals(totalScore: 0, scoreDiff: 0) }
        return PlayerTotals(totalScore: totalScore, scoreDiff: totalScore - totalPar)
    }

    static func clubUsage(round: Round, userId: String) -> [ClubStat] {
        clubUsage(rounds: [round], userId: userId)
    }

    static func clubUsage(rounds: [Round], userId: String) -> [ClubStat] {
        var counts: [String: Int] = [:]
        var total = 0
        for round in rounds {
            for hole in round.holes {
                for club in hole.shots[userId]?.resolvedClubs ?? [] {
                    if club == "Неизвестно" { continue }
                    counts[club, default: 0] += 1
                    total += 1
                }
            }
        }
        if total == 0 { return [] }
        return counts
            .map { club, count in
                ClubStat(club: club, count: count,
                         percent: Int((Double(count) / Double(total) * 100).rounded()))
            }
            .sorted { a, b in
                if a.count != b.count { return a.count > b.count }
                return a.club < b.club
            }
    }

    static func leaderboard(round: Round) -> [LeaderboardEntry] {
        var entries: [LeaderboardEntry] = []
        for uid in round.playerIds {
            guard let player = round.players[uid] else { continue }
            let totals = playerTotals(round: round, userId: uid)
            let thru = round.holes.filter { ($0.shots[uid]?.count ?? 0) > 0 }.count
            entries.append(LeaderboardEntry(
                uid: uid, name: player.name, avatar: player.avatar,
                totalScore: totals.totalScore, scoreDiff: totals.scoreDiff, thru: thru
            ))
        }
        return entries.sorted { a, b in
            if a.thru == 0 && b.thru > 0 { return false }
            if b.thru == 0 && a.thru > 0 { return true }
            if a.scoreDiff != b.scoreDiff { return a.scoreDiff < b.scoreDiff }
            if a.totalScore != b.totalScore { return a.totalScore < b.totalScore }
            return a.name < b.name
        }
    }

    static func playerStats(rounds: [Round], userId: String) -> PlayerStats {
        var totalShots = 0
        var bestScore: Int?
        var bestScoreDiff: Int?
        var roundsPlayed = 0
        var totalHolesPlayed = 0
        var holeStats = HoleResultStats()

        for round in rounds {
            let totals = playerTotals(round: round, userId: userId)
            if totals.totalScore == 0 { continue }
            roundsPlayed += 1
            totalShots += totals.totalScore
            if bestScore == nil || totals.totalScore < bestScore! { bestScore = totals.totalScore }
            if bestScoreDiff == nil || totals.scoreDiff < bestScoreDiff! { bestScoreDiff = totals.scoreDiff }

            for hole in round.holes {
                let count = hole.shots[userId]?.count ?? 0
                if count == 0 { continue }
                totalHolesPlayed += 1
                let delta = count - hole.par
                if delta <= -2 { holeStats.eagle += 1 }
                else if delta == -1 { holeStats.birdie += 1 }
                else if delta == 0 { holeStats.par += 1 }
                else if delta == 1 { holeStats.bogey += 1 }
                else if delta == 2 { holeStats.double += 1 }
                else { holeStats.worse += 1 }
            }
        }

        let avgShots = roundsPlayed > 0
            ? (Double(totalShots) / Double(roundsPlayed) * 100).rounded() / 100
            : 0
        return PlayerStats(
            roundsPlayed: roundsPlayed, totalShots: totalShots, avgShots: avgShots,
            bestScore: bestScore, bestScoreDiff: bestScoreDiff,
            holeStats: holeStats, totalHolesPlayed: totalHolesPlayed
        )
    }

    static func handicap(rounds: [Round], userId: String) -> HandicapResult? {
        var diffs: [Int] = []
        for round in rounds {
            guard round.status == .finished else { continue }
            let totals = playerTotals(round: round, userId: userId)
            if totals.totalScore == 0 { continue }
            diffs.append(totals.scoreDiff)
        }
        if diffs.count < 3 { return nil }
        let recent = Array(diffs.prefix(20))
        let bestN = min(8, recent.count)
        let best = recent.sorted().prefix(bestN)
        let avg = Double(best.reduce(0, +)) / Double(bestN)
        let index = (avg * 0.96 * 10).rounded() / 10
        return HandicapResult(index: index, basedOnRounds: recent.count, bestUsed: bestN)
    }

    static func matchPlayStatus(round: Round, uidA: String, uidB: String) -> MatchPlayStatus {
        var aUp = 0, bUp = 0, holesPlayed = 0
        for hole in round.holes {
            let aCount = hole.shots[uidA]?.count ?? 0
            let bCount = hole.shots[uidB]?.count ?? 0
            if aCount == 0 || bCount == 0 { continue }
            holesPlayed += 1
            if aCount < bCount { aUp += 1 }
            else if bCount < aCount { bUp += 1 }
        }
        let delta = abs(aUp - bUp)
        let holesRemaining = round.holes.count - holesPlayed
        let closed = delta > holesRemaining
        let leaderUid = aUp > bUp ? uidA : (bUp > aUp ? uidB : nil)
        let trailerUid = leaderUid == uidA ? uidB : (leaderUid == uidB ? uidA : nil)

        let label: String
        if round.status == .finished || holesRemaining == 0 {
            label = delta == 0 ? "AS" : "\(delta) UP"
        } else if closed {
            label = "\(delta)&\(holesRemaining)"
        } else if delta == 0 {
            label = "AS"
        } else {
            label = "\(delta) UP"
        }
        return MatchPlayStatus(
            leaderUid: leaderUid, trailerUid: trailerUid,
            holesPlayed: holesPlayed, holesRemaining: holesRemaining,
            delta: delta, label: label, closed: closed
        )
    }
}
```

В `ios/SmartGolfCaddy/Models/Round.swift` дописать в конец файла:

```swift
// Порт TEE_LABELS из src/types/index.ts — метки и цвета тии.
extension TeeColor {
    var label: String {
        switch self {
        case .pro: return "Pro"
        case .men: return "Мужские"
        case .senior: return "Сеньорские"
        case .ladies: return "Женские"
        }
    }

    var teeDescription: String {
        switch self {
        case .pro: return "Чемпионские · +10%"
        case .men: return "Стандартные"
        case .senior: return "Чуть ближе · −10%"
        case .ladies: return "Ближе всего · −20%"
        }
    }

    var bgHex: String {
        switch self {
        case .pro: return "#0A3010"
        case .men: return "#FFFFFF"
        case .senior: return "#FFC107"
        case .ladies: return "#F44336"
        }
    }

    var textHex: String {
        switch self {
        case .pro: return "#FFFFFF"
        case .men: return "#1A1C1C"
        case .senior: return "#1A1C1C"
        case .ladies: return "#FFFFFF"
        }
    }
}
```

- [ ] **Step 4: Прогнать — зелёные.** Стандартная тест-команда, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/SmartGolfCaddy/Models/Scoring.swift ios/SmartGolfCaddy/Models/Round.swift ios/SmartGolfCaddyTests/ScoringTests.swift
git commit -m "feat(ios): scoring engine — port of scoring.ts with tee labels + tests"
```

---

### Task 2: RoundsService — Firestore + callable (TDD для чистых частей)

**Files:**
- Create: `ios/SmartGolfCaddy/Services/RoundsService.swift`
- Modify: `ios/SmartGolfCaddy/Models/Round.swift` (firestoreData у PlayerInfo и HoleConfig)
- Test: `ios/SmartGolfCaddyTests/RoundsServiceTests.swift`

**Interfaces:**
- Consumes: `FirebaseService.db/.functions/.normalizedDates`, `callableDict`, `RecordShotInput`, `UpdateHoleConfigInput`, `Round(id:data:)`, `TeeColor.multiplier`, `DEFAULT_HOLE_PARS`-аналог (создаём здесь).
- Produces (для Tasks 3–7):
  - `Rounds.defaultHolePars(totalHoles:) -> [Int]` (9/18), `Rounds.buildDefaultHoles(totalHoles:tee:) -> [HoleConfig]`, `Rounds.generateLobbyCode() -> String`
  - `RoundsService.createSoloRound(hostId:hostInfo:courseId:courseName:totalHoles:tee:) async throws -> String`
  - `RoundsService.finishRound(roundId:) async throws`
  - `RoundsService.subscribeToRound(roundId:onChange:onError:) -> () -> Void` (onChange получает `Round`)
  - `RoundsService.getUserRounds(userId:limitTo:) async throws -> [Round]`
  - `RoundsService.recordShot(roundId:holeIndex:targetUid:clubs:) async throws`
  - `RoundsService.updateHoleConfig(roundId:holeIndex:par:distanceMeters:) async throws`
  - `PlayerInfo.firestoreData: [String: Any]`, `HoleConfig.firestoreData: [String: Any]`, `PlayerInfo(name:avatar:totalScore:scoreDiff:email:)` (memberwise-инициализатор)

- [ ] **Step 1: Падающие тесты (чистая логика: лунки, код лобби, сериализация)**

```swift
// ios/SmartGolfCaddyTests/RoundsServiceTests.swift
import XCTest
@testable import SmartGolfCaddy

final class RoundsServiceTests: XCTestCase {

    func testDefaultHoleParsShape() {
        XCTAssertEqual(Rounds.defaultHolePars(totalHoles: 9), [4, 3, 5, 4, 4, 3, 5, 4, 4])
        XCTAssertEqual(Rounds.defaultHolePars(totalHoles: 18).count, 18)
        XCTAssertEqual(Rounds.defaultHolePars(totalHoles: 18).reduce(0, +), 72)
    }

    func testBuildDefaultHolesDistances() {
        // База: par3=150, par5=480, par4=360; men ×1.0
        let holes = Rounds.buildDefaultHoles(totalHoles: 9, tee: .men)
        XCTAssertEqual(holes.count, 9)
        XCTAssertEqual(holes[0].par, 4); XCTAssertEqual(holes[0].distanceMeters, 360)
        XCTAssertEqual(holes[1].par, 3); XCTAssertEqual(holes[1].distanceMeters, 150)
        XCTAssertEqual(holes[2].par, 5); XCTAssertEqual(holes[2].distanceMeters, 480)
        XCTAssertEqual(holes[0].holeNumber, 1)
        XCTAssertTrue(holes.allSatisfy { $0.shots.isEmpty })
    }

    func testBuildDefaultHolesTeeMultiplier() {
        let ladies = Rounds.buildDefaultHoles(totalHoles: 9, tee: .ladies)
        XCTAssertEqual(ladies[1].distanceMeters, 120)  // 150 × 0.8
        let pro = Rounds.buildDefaultHoles(totalHoles: 9, tee: .pro)
        XCTAssertEqual(pro[2].distanceMeters, 528)     // 480 × 1.1
    }

    func testGenerateLobbyCode() {
        let allowed = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        for _ in 0..<50 {
            let code = Rounds.generateLobbyCode()
            XCTAssertEqual(code.count, 6)
            XCTAssertTrue(code.allSatisfy { allowed.contains($0) })
        }
    }

    func testHoleConfigFirestoreRoundTrip() {
        var config = Rounds.buildDefaultHoles(totalHoles: 9, tee: .men)[0]
        config.shots["u1"] = HoleShots(count: 2, clubs: ["Driver", "Putter"], legacyClub: nil, updatedAt: nil)
        let restored = HoleConfig(data: config.firestoreData)
        XCTAssertEqual(restored?.holeNumber, config.holeNumber)
        XCTAssertEqual(restored?.par, config.par)
        XCTAssertEqual(restored?.distanceMeters, config.distanceMeters)
        XCTAssertEqual(restored?.shots["u1"]?.resolvedClubs, ["Driver", "Putter"])
    }

    func testPlayerInfoFirestoreRoundTrip() {
        let info = PlayerInfo(name: "Джамбулат", avatar: "https://a.jpg", totalScore: 0, scoreDiff: 0, email: "x@y.z")
        let restored = PlayerInfo(data: info.firestoreData)
        XCTAssertEqual(restored, info)
        // email nil → ключ отсутствует
        let noEmail = PlayerInfo(name: "А", avatar: "", totalScore: 0, scoreDiff: 0, email: nil)
        XCTAssertNil(noEmail.firestoreData["email"])
    }
}
```

- [ ] **Step 2: Прогнать — падает компиляцией.**

- [ ] **Step 3: Реализация**

В `ios/SmartGolfCaddy/Models/Round.swift`: у `PlayerInfo` добавить memberwise-инициализатор и `firestoreData`; у `HoleConfig` и `HoleShots` — `firestoreData`:

```swift
// PlayerInfo — дописать внутри struct:
    init(name: String, avatar: String, totalScore: Int, scoreDiff: Int, email: String?) {
        self.name = name
        self.avatar = avatar
        self.totalScore = totalScore
        self.scoreDiff = scoreDiff
        self.email = email
    }

    var firestoreData: [String: Any] {
        var d: [String: Any] = ["name": name, "avatar": avatar,
                                "totalScore": totalScore, "scoreDiff": scoreDiff]
        if let email { d["email"] = email }
        return d
    }

// HoleShots — дописать внутри struct:
    var firestoreData: [String: Any] {
        var d: [String: Any] = ["count": count, "clubs": clubs]
        if let legacyClub { d["club"] = legacyClub }
        if let updatedAt { d["updatedAt"] = updatedAt }
        return d
    }

// HoleConfig — дописать внутри struct:
    var firestoreData: [String: Any] {
        [
            "holeNumber": holeNumber,
            "par": par,
            "distanceMeters": distanceMeters,
            "shots": shots.mapValues { $0.firestoreData },
        ]
    }
```

```swift
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
```

Примечание: в `buildDefaultHoles` конструирование через словарь + `HoleConfig(data:)` выглядит окольным, но переиспользует единственный инициализатор HoleConfig (без введения второго memberwise) — осознанный выбор.

- [ ] **Step 4: Прогнать — зелёные.**

- [ ] **Step 5: Commit**

```bash
git add ios/SmartGolfCaddy/Services/RoundsService.swift ios/SmartGolfCaddy/Models/Round.swift ios/SmartGolfCaddyTests/RoundsServiceTests.swift
git commit -m "feat(ios): rounds service — solo create/finish/subscribe/query + callable shots"
```

---

### Task 3: Офлайн-очередь ударов (TDD)

**Files:**
- Create: `ios/SmartGolfCaddy/Services/ShotQueue.swift`
- Modify: `ios/SmartGolfCaddy/App/AppDelegate.swift` (initShotSync на старте)
- Test: `ios/SmartGolfCaddyTests/ShotQueueTests.swift`

**Interfaces:**
- Consumes: `RoundsService.recordShot` (как дефолтный sender), `FunctionsErrorDomain`-коды.
- Produces (для Task 6):
  - `struct PendingShot: Codable, Equatable { roundId, holeIndex, targetUid, clubs, updatedAt }`
  - `final class ShotQueue` c `static let shared`; init(storeURL:sender:isOnline:) для тестов
  - `func pendingShot(roundId:holeIndex:targetUid:) -> PendingShot?`
  - `func pendingCount(roundId:) -> Int`
  - `func recordShotQueued(roundId:holeIndex:targetUid:clubs:) async -> RecordOutcome` где `enum RecordOutcome { case synced; case queued; case rejected(Error) }` (веб бросает permanent — у нас явный кейс, VM делает rollback)
  - `func flush() async -> Int` (remaining)
  - `func initSync()` (flush на старте + NWPathMonitor на восстановление сети)
  - `Notification.Name.shotQueueDidChange` — постится после каждого изменения очереди

- [ ] **Step 1: Падающие тесты**

```swift
// ios/SmartGolfCaddyTests/ShotQueueTests.swift
import XCTest
@testable import SmartGolfCaddy

final class ShotQueueTests: XCTestCase {
    private var storeURL: URL!

    override func setUp() {
        super.setUp()
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shotqueue-test-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeURL)
        super.tearDown()
    }

    private func makeQueue(
        sender: @escaping (PendingShot) async throws -> Void = { _ in },
        online: @escaping () -> Bool = { true }
    ) -> ShotQueue {
        ShotQueue(storeURL: storeURL, sender: sender, isOnline: online)
    }

    private func permanentError() -> NSError {
        NSError(domain: "com.firebase.functions", code: 7,
                userInfo: ["FIRFunctionsErrorCode": "permission-denied"])
    }

    func testSyncedPathClearsQueue() async {
        let queue = makeQueue()
        let outcome = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u", clubs: ["Driver"])
        guard case .synced = outcome else { return XCTFail("ожидали synced") }
        XCTAssertNil(queue.pendingShot(roundId: "r", holeIndex: 0, targetUid: "u"))
        XCTAssertEqual(queue.pendingCount(roundId: "r"), 0)
    }

    func testOfflineStaysQueuedAndSurvivesReload() async {
        let queue = makeQueue(online: { false })
        let outcome = await queue.recordShotQueued(roundId: "r", holeIndex: 2, targetUid: "u", clubs: ["7i", "Putter"])
        guard case .queued = outcome else { return XCTFail("ожидали queued") }
        XCTAssertEqual(queue.pendingShot(roundId: "r", holeIndex: 2, targetUid: "u")?.clubs, ["7i", "Putter"])
        // «Перезапуск»: новый инстанс над тем же файлом
        let reloaded = makeQueue(online: { false })
        XCTAssertEqual(reloaded.pendingShot(roundId: "r", holeIndex: 2, targetUid: "u")?.clubs, ["7i", "Putter"])
        XCTAssertEqual(reloaded.pendingCount(roundId: "r"), 1)
    }

    func testLastWriteWinsPerSlot() async {
        let queue = makeQueue(online: { false })
        _ = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u", clubs: ["Driver"])
        _ = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u", clubs: ["Driver", "PW"])
        XCTAssertEqual(queue.pendingShot(roundId: "r", holeIndex: 0, targetUid: "u")?.clubs, ["Driver", "PW"])
        XCTAssertEqual(queue.pendingCount(roundId: "r"), 1)
    }

    func testTransientFailureStaysQueued() async {
        let queue = makeQueue(sender: { _ in
            throw NSError(domain: "com.firebase.functions", code: 14,
                          userInfo: ["FIRFunctionsErrorCode": "unavailable"])
        })
        let outcome = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u", clubs: ["Driver"])
        guard case .queued = outcome else { return XCTFail("ожидали queued") }
        XCTAssertNotNil(queue.pendingShot(roundId: "r", holeIndex: 0, targetUid: "u"))
    }

    func testPermanentFailureDropsAndReports() async {
        let queue = makeQueue(sender: { _ in throw self.permanentError() })
        let outcome = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u", clubs: ["Driver"])
        guard case .rejected = outcome else { return XCTFail("ожидали rejected") }
        XCTAssertNil(queue.pendingShot(roundId: "r", holeIndex: 0, targetUid: "u"))
    }

    func testFlushSendsAllAndStopsOnTransient() async {
        var sent: [String] = []
        var failNext = false
        let queue = makeQueue(sender: { shot in
            if failNext {
                throw NSError(domain: "com.firebase.functions", code: 14,
                              userInfo: ["FIRFunctionsErrorCode": "unavailable"])
            }
            sent.append("\(shot.roundId):\(shot.holeIndex)")
        }, online: { false })
        _ = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u", clubs: ["Driver"])
        _ = await queue.recordShotQueued(roundId: "r", holeIndex: 1, targetUid: "u", clubs: ["7i"])
        XCTAssertEqual(queue.pendingCount(roundId: "r"), 2)

        let remaining = await queue.flush()
        XCTAssertEqual(remaining, 0)
        XCTAssertEqual(sent.count, 2)

        _ = await queue.recordShotQueued(roundId: "r", holeIndex: 2, targetUid: "u", clubs: ["PW"])
        failNext = true
        let remaining2 = await queue.flush()
        XCTAssertEqual(remaining2, 1)  // transient — остался в очереди
    }

    func testFlushDropsPermanent() async {
        let queue = makeQueue(sender: { _ in throw self.permanentError() }, online: { false })
        _ = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u", clubs: ["Driver"])
        let remaining = await queue.flush()
        XCTAssertEqual(remaining, 0)  // permanent дропнут, очередь не заклинена
    }
}
```

- [ ] **Step 2: Прогнать — падает компиляцией.**

- [ ] **Step 3: Реализация**

```swift
// ios/SmartGolfCaddy/Services/ShotQueue.swift
// Порт src/services/shotQueue.ts. Удары НИКОГДА не шлём напрямую —
// только через recordShotQueued: сначала durable-запись в файл, потом
// попытка отправки. Безопасно, т.к. recordShot идемпотентна (пишет весь
// массив clubs слота) — очереди достаточно последнего состояния на слот
// (last-write-wins).
import FirebaseFunctions
import Foundation
import Network

struct PendingShot: Codable, Equatable {
    var roundId: String
    var holeIndex: Int
    var targetUid: String
    var clubs: [String]
    var updatedAt: TimeInterval
}

enum RecordOutcome {
    case synced
    case queued
    case rejected(Error)
}

extension Notification.Name {
    static let shotQueueDidChange = Notification.Name("shotQueueDidChange")
}

final class ShotQueue: @unchecked Sendable {

    static let shared = ShotQueue(
        storeURL: ShotQueue.defaultStoreURL(),
        sender: { shot in
            try await RoundsService.recordShot(
                roundId: shot.roundId, holeIndex: shot.holeIndex,
                targetUid: shot.targetUid, clubs: shot.clubs
            )
        },
        isOnline: { ShotQueue.pathMonitorOnline }
    )

    // Ошибки сервера, которые не исправятся повтором — дроп из очереди.
    private static let permanentCodes: Set<FunctionsErrorCode> = [
        .permissionDenied, .unauthenticated, .failedPrecondition,
        .invalidArgument, .notFound,
    ]

    private let storeURL: URL
    private let sender: (PendingShot) async throws -> Void
    private let isOnline: () -> Bool
    private let ioQueue = DispatchQueue(label: "sgc.shotqueue.io")
    private var flushing = false

    init(storeURL: URL,
         sender: @escaping (PendingShot) async throws -> Void,
         isOnline: @escaping () -> Bool) {
        self.storeURL = storeURL
        self.sender = sender
        self.isOnline = isOnline
    }

    // MARK: хранилище (JSON-файл, ключ слота "round:hole:uid")

    private func slotKey(_ roundId: String, _ holeIndex: Int, _ targetUid: String) -> String {
        "\(roundId):\(holeIndex):\(targetUid)"
    }

    private func load() -> [String: PendingShot] {
        ioQueue.sync {
            guard let data = try? Data(contentsOf: storeURL) else { return [:] }
            return (try? JSONDecoder().decode([String: PendingShot].self, from: data)) ?? [:]
        }
    }

    private func persist(_ map: [String: PendingShot]) {
        ioQueue.sync {
            if let data = try? JSONEncoder().encode(map) {
                try? data.write(to: storeURL, options: .atomic)
            }
        }
        NotificationCenter.default.post(name: .shotQueueDidChange, object: nil)
    }

    // MARK: публичный интерфейс

    func pendingShot(roundId: String, holeIndex: Int, targetUid: String) -> PendingShot? {
        load()[slotKey(roundId, holeIndex, targetUid)]
    }

    func pendingCount(roundId: String) -> Int {
        load().values.filter { $0.roundId == roundId }.count
    }

    func recordShotQueued(roundId: String, holeIndex: Int, targetUid: String, clubs: [String]) async -> RecordOutcome {
        let entry = PendingShot(roundId: roundId, holeIndex: holeIndex,
                                targetUid: targetUid, clubs: clubs,
                                updatedAt: Date().timeIntervalSince1970)
        var map = load()
        map[slotKey(roundId, holeIndex, targetUid)] = entry
        persist(map)

        guard isOnline() else { return .queued }

        do {
            try await sender(entry)
            dequeueIfMatches(entry)
            return .synced
        } catch {
            if Self.isPermanent(error) {
                dequeueIfMatches(entry)
                return .rejected(error)
            }
            return .queued
        }
    }

    /// Снять слот, только если в очереди всё ещё ровно то, что мы отправили —
    /// не затирает более новый удар, записанный пока шла отправка.
    private func dequeueIfMatches(_ entry: PendingShot) {
        var map = load()
        let key = slotKey(entry.roundId, entry.holeIndex, entry.targetUid)
        if let current = map[key], current.clubs == entry.clubs {
            map.removeValue(forKey: key)
            persist(map)
        }
    }

    @discardableResult
    func flush() async -> Int {
        if flushing { return load().count }
        flushing = true
        defer { flushing = false }

        for (key, entry) in load() {
            do {
                try await sender(entry)
                var current = load()
                if let live = current[key], live.updatedAt == entry.updatedAt {
                    current.removeValue(forKey: key)
                    persist(current)
                }
            } catch {
                if Self.isPermanent(error) {
                    var current = load()
                    if let live = current[key], live.updatedAt == entry.updatedAt {
                        current.removeValue(forKey: key)
                        persist(current)
                    }
                    continue  // дроп и дальше
                }
                break  // transient — стоп до следующего online-события
            }
        }
        return load().count
    }

    // MARK: сеть и автозапуск

    private static var monitor: NWPathMonitor?
    private static var pathMonitorOnline = true

    func initSync() {
        guard Self.monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let wasOffline = !Self.pathMonitorOnline
            Self.pathMonitorOnline = online
            if online && wasOffline {
                Task { await self?.flush() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "sgc.shotqueue.network"))
        Self.monitor = monitor
        Task { await flush() }
    }

    private static func isPermanent(_ error: Error) -> Bool {
        let ns = error as NSError
        // Боевой путь: NSError от FirebaseFunctions c FunctionsErrorDomain.
        if ns.domain == FunctionsErrorDomain,
           let code = FunctionsErrorCode(rawValue: ns.code) {
            return permanentCodes.contains(code)
        }
        // Тестовый/переносимый путь: домен functions + строковый код.
        if let raw = ns.userInfo["FIRFunctionsErrorCode"] as? String {
            let mapped: [String: FunctionsErrorCode] = [
                "permission-denied": .permissionDenied,
                "unauthenticated": .unauthenticated,
                "failed-precondition": .failedPrecondition,
                "invalid-argument": .invalidArgument,
                "not-found": .notFound,
                "unavailable": .unavailable,
            ]
            if let code = mapped[raw] { return permanentCodes.contains(code) }
        }
        return false
    }

    private static func defaultStoreURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pending-shots-v1.json")
    }
}
```

ВНИМАНИЕ (для исполнителя): `import FirebaseFunctions` в ShotQueue.swift легален (Services/). Но ТЕСТ (`ShotQueueTests`) Firebase НЕ импортирует — он передаёт NSError с доменом-строкой `"com.firebase.functions"`. Проверь фактическое значение константы `FunctionsErrorDomain` (grep по SourcePackages: `grep -rn "FunctionsErrorDomain\s*=" ~/Library/Developer/Xcode/DerivedData/SmartGolfCaddy-local/SourcePackages/checkouts/firebase-ios-sdk/FirebaseFunctions/Sources/ | head -3`). Если домен иной — поправь строку в тестах под фактический ЛИБО положись на второй путь isPermanent (userInfo["FIRFunctionsErrorCode"]) — тогда в тестах домен не важен, а транзиентная ветка тестов должна использовать код, отсутствующий в permanent-набора (unavailable уже так).

В `AppDelegate.application(_:didFinishLaunchingWithOptions:)` после `FirebaseApp.configure()` добавить:

```swift
        ShotQueue.shared.initSync()
```

- [ ] **Step 4: Прогнать — зелёные.**

- [ ] **Step 5: Commit**

```bash
git add ios/SmartGolfCaddy/Services/ShotQueue.swift ios/SmartGolfCaddy/App/AppDelegate.swift ios/SmartGolfCaddyTests/ShotQueueTests.swift
git commit -m "feat(ios): durable offline shot queue — port of shotQueue.ts + tests"
```

---

### Task 4: Роутер, стор, компонент кнопки, экран Home

**Files:**
- Create: `ios/SmartGolfCaddy/App/AppRouter.swift`
- Create: `ios/SmartGolfCaddy/ViewModels/AppStore.swift`
- Create: `ios/SmartGolfCaddy/Views/Components/DSButton.swift`
- Create: `ios/SmartGolfCaddy/ViewModels/HomeViewModel.swift`
- Create: `ios/SmartGolfCaddy/Views/HomeView.swift`
- Modify: `ios/SmartGolfCaddy/App/RootView.swift` (NavigationStack + HomeView вместо HomePlaceholderView)
- Delete: `ios/SmartGolfCaddy/Views/HomePlaceholderView.swift` (заменён HomeView; `git rm`). `DiagnosticsView.swift` НЕ удалять — остаётся неподключённым DEBUG-инструментом, в его шапку добавить строку-комментарий «// Не подключён к UI с Фазы 2a; для проверки канала подключить временно в HomeView (#if DEBUG)».
- Test: `ios/SmartGolfCaddyTests/HomeViewModelTests.swift`

**Interfaces:**
- Consumes: `RoundsService.getUserRounds`, `Scoring.playerTotals`, `SessionViewModel`, `pluralRu`, DS-токены.
- Produces (для Tasks 5–7):
  - `enum Route: Hashable { case roundSetup; case hole(roundId: String, number: Int); case results(roundId: String) }`
  - `@Observable @MainActor final class AppRouter { var path: [Route]; func push(_:); func replaceLast(_:); func popToRoot() }` — в Environment
  - `@Observable @MainActor final class AppStore { var lastClubUsed: String = "Driver" }` — в Environment
  - `DSButton(title:icon:style:action:)` где `style: .primary | .secondary` — full-width капсула, uppercase+tracking, min-height 48
  - `HomeViewModel.load(userId:) async`; `.activeRound: Round?`; `.recentFinished: [Round]`; `.loadError: Bool`; статические `resumeHoleNumber(round:userId:) -> Int`, `resumeSubtitle(round:userId:) -> String`

- [ ] **Step 1: Падающие тесты (логика resume)**

```swift
// ios/SmartGolfCaddyTests/HomeViewModelTests.swift
import XCTest
@testable import SmartGolfCaddy

final class HomeViewModelTests: XCTestCase {
    private func activeRound(shotsOnHoles: [Int]) -> Round {
        var holes: [[String: Any]] = []
        for n in 1...9 {
            var shots: [String: [String: Any]] = [:]
            if shotsOnHoles.contains(n) {
                shots["u1"] = ["count": 4, "clubs": ["Driver", "7i", "PW", "Putter"]]
            }
            holes.append(["holeNumber": n, "par": 4, "distanceMeters": 360, "shots": shots])
        }
        return Round(id: "r", data: [
            "courseId": "c", "courseName": "Поле", "totalHoles": 9,
            "lobbyCode": "ABC234", "status": "active", "hostId": "u1",
            "players": ["u1": ["name": "А", "avatar": "", "totalScore": 0, "scoreDiff": 0]],
            "playerIds": ["u1"], "holes": holes,
            "startedAt": Date(), "createdAt": Date(),
        ])!
    }

    @MainActor
    func testResumeTargetsFirstUnplayedHole() {
        let round = activeRound(shotsOnHoles: [1, 2])
        XCTAssertEqual(HomeViewModel.resumeHoleNumber(round: round, userId: "u1"), 3)
    }

    @MainActor
    func testResumeAllPlayedTargetsLastHole() {
        let round = activeRound(shotsOnHoles: Array(1...9))
        XCTAssertEqual(HomeViewModel.resumeHoleNumber(round: round, userId: "u1"), 9)
    }

    @MainActor
    func testResumeSubtitleCountsPlayed() {
        let round = activeRound(shotsOnHoles: [1, 3, 5])
        XCTAssertEqual(HomeViewModel.resumeSubtitle(round: round, userId: "u1"), "Пройдено 3 из 9")
    }
}
```

- [ ] **Step 2: Прогнать — падает компиляцией.**

- [ ] **Step 3: Реализация**

```swift
// ios/SmartGolfCaddy/App/AppRouter.swift
import Foundation
import Observation

enum Route: Hashable {
    case roundSetup
    case hole(roundId: String, number: Int)
    case results(roundId: String)
}

@Observable
@MainActor
final class AppRouter {
    var path: [Route] = []

    func push(_ route: Route) {
        path.append(route)
    }

    /// Замена вершины стека — переход лунка→лунка и лунка→итоги без роста стека.
    func replaceLast(_ route: Route) {
        if path.isEmpty {
            path = [route]
        } else {
            path[path.count - 1] = route
        }
    }

    func popToRoot() {
        path.removeAll()
    }
}
```

```swift
// ios/SmartGolfCaddy/ViewModels/AppStore.swift
// Зеркало useAppStore веба: единственное поле — клюшка по умолчанию для
// следующей лунки. Живёт в памяти процесса, Firestore не трогает.
import Foundation
import Observation

@Observable
@MainActor
final class AppStore {
    var lastClubUsed: String = "Driver"
}
```

```swift
// ios/SmartGolfCaddy/Views/Components/DSButton.swift
// Аналог веб-компонента Button: full-width капсула, uppercase, иконка слева.
import SwiftUI

struct DSButton: View {
    enum Style {
        case primary, secondary
    }

    let title: String
    var icon: String? = nil
    var style: Style = .primary
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(DSFont.labelLG)
                    .tracking(1.5)
            }
            .textCase(.uppercase)
            .frame(maxWidth: .infinity)
            .frame(minHeight: DS.touchTarget)
        }
        .background(style == .primary ? DSColor.primary : DSColor.surfaceContainer)
        .foregroundStyle(style == .primary ? DSColor.onPrimary : DSColor.onSurface)
        .clipShape(Capsule())
        .opacity(disabled ? 0.5 : 1)
        .disabled(disabled)
    }
}
```

```swift
// ios/SmartGolfCaddy/ViewModels/HomeViewModel.swift
import Foundation
import Observation

@Observable
@MainActor
final class HomeViewModel {
    var activeRound: Round?
    var recentFinished: [Round] = []
    var loadError = false
    var loading = false

    func load(userId: String) async {
        loading = true
        loadError = false
        defer { loading = false }
        do {
            // Окно 10: Home показывает 3 последних finished + ищет незавершённый.
            let rounds = try await RoundsService.getUserRounds(userId: userId, limitTo: 10)
            recentFinished = Array(rounds.filter { $0.status == .finished }.prefix(3))
            activeRound = rounds.first { $0.status == .active || $0.status == .lobby }
        } catch {
            loadError = true
        }
    }

    /// Первая лунка без ударов игрока; если все сыграны — последняя.
    static func resumeHoleNumber(round: Round, userId: String) -> Int {
        if let index = round.holes.firstIndex(where: { ($0.shots[userId]?.count ?? 0) == 0 }) {
            return index + 1
        }
        return round.totalHoles
    }

    static func resumeSubtitle(round: Round, userId: String) -> String {
        let played = round.holes.filter { ($0.shots[userId]?.count ?? 0) > 0 }.count
        return "Пройдено \(played) из \(round.totalHoles)"
    }
}
```

```swift
// ios/SmartGolfCaddy/Views/HomeView.swift
import SwiftUI

struct HomeView: View {
    @Environment(SessionViewModel.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var model = HomeViewModel()

    private var firstName: String {
        let name = session.profile?.name ?? "Голфер"
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let active = model.activeRound {
                    resumeCard(active)
                        .padding(.horizontal, DS.screenPadding)
                        .padding(.top, 24)
                }
                VStack(spacing: 12) {
                    DSButton(title: "Начать новый раунд", icon: "plus") {
                        router.push(.roundSetup)
                    }
                }
                .padding(.horizontal, DS.screenPadding)
                .padding(.top, 24)

                if model.loadError {
                    errorBanner
                        .padding(.horizontal, DS.screenPadding)
                        .padding(.top, 24)
                }

                if !model.recentFinished.isEmpty {
                    recentSection
                        .padding(.horizontal, DS.screenPadding)
                        .padding(.top, 32)
                }
            }
            .padding(.bottom, 32)
        }
        .background(DSColor.surface)
        .task {
            if let uid = AuthService.currentUserId {
                await model.load(userId: uid)
            }
        }
        .refreshable {
            if let uid = AuthService.currentUserId {
                await model.load(userId: uid)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ДОБРО ПОЖАЛОВАТЬ")
                        .font(DSFont.labelLG)
                        .tracking(2.5)
                        .foregroundStyle(DSColor.onPrimary.opacity(0.7))
                    Text(firstName)
                        .font(DSFont.headlineLG)
                        .foregroundStyle(DSColor.onPrimary)
                }
                Spacer()
                Button {
                    session.signOut()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 18))
                        .foregroundStyle(DSColor.onPrimary.opacity(0.8))
                        .frame(minWidth: DS.touchTarget, minHeight: DS.touchTarget)
                }
                .accessibilityLabel("Выйти")
            }
        }
        .padding(.horizontal, DS.screenPadding)
        .padding(.top, 40)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [DSColor.primaryContainer, DSColor.primary],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private func resumeCard(_ round: Round) -> some View {
        Button {
            guard let uid = AuthService.currentUserId else { return }
            router.push(.hole(roundId: round.id,
                              number: HomeViewModel.resumeHoleNumber(round: round, userId: uid)))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .foregroundStyle(DSColor.onPrimary)
                    .frame(width: 40, height: 40)
                    .background(DSColor.primary)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("ПРОДОЛЖИТЬ РАУНД")
                        .font(DSFont.labelMD)
                        .tracking(1.2)
                        .foregroundStyle(DSColor.primary)
                    Text(round.courseName)
                        .font(DSFont.bodyMD)
                        .foregroundStyle(DSColor.onSurface)
                        .lineLimit(1)
                    if let uid = AuthService.currentUserId {
                        Text(HomeViewModel.resumeSubtitle(round: round, userId: uid))
                            .font(DSFont.labelMD)
                            .foregroundStyle(DSColor.onSurfaceVariant)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(DSColor.primary)
            }
            .padding(16)
            .background(DSColor.primaryContainer.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DS.cornerRadius)
                    .stroke(DSColor.primary.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
    }

    private var errorBanner: some View {
        HStack(spacing: 12) {
            Text("Не удалось загрузить раунды")
                .font(DSFont.labelLG)
                .foregroundStyle(DSColor.onSurface)
            Spacer()
            Button("Повторить") {
                Task {
                    if let uid = AuthService.currentUserId {
                        await model.load(userId: uid)
                    }
                }
            }
            .font(DSFont.labelLG)
            .foregroundStyle(DSColor.primary)
        }
        .padding(14)
        .background(DSColor.errorContainer.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Последние раунды")
                .font(DSFont.titleLG)
                .foregroundStyle(DSColor.onSurface)
            ForEach(model.recentFinished) { round in
                Button {
                    router.push(.results(roundId: round.id))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(round.courseName)
                                .font(DSFont.bodyMD)
                                .foregroundStyle(DSColor.onSurface)
                                .lineLimit(1)
                            Text(subtitle(for: round))
                                .font(DSFont.labelMD)
                                .foregroundStyle(DSColor.onSurfaceVariant)
                        }
                        Spacer()
                        if let uid = AuthService.currentUserId {
                            Text(scoreSummary(round, uid: uid))
                                .font(DSFont.titleLG)
                                .foregroundStyle(DSColor.primary)
                                .monospacedDigit()
                        }
                    }
                    .padding(14)
                    .background(DSColor.surfaceContainerLowest)
                    .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.cornerRadius)
                            .stroke(DSColor.outlineVariant.opacity(0.25))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func subtitle(for round: Round) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM yyyy"
        let date = formatter.string(from: round.createdAt)
        return "\(date) · \(round.totalHoles) \(pluralRu(round.totalHoles, "лунка", "лунки", "лунок"))"
    }

    private func scoreSummary(_ round: Round, uid: String) -> String {
        guard round.players[uid] != nil else { return "" }
        let totals = Scoring.playerTotals(round: round, userId: uid)
        let sign = totals.scoreDiff >= 0 ? "+" : ""
        return "\(totals.totalScore) (\(sign)\(totals.scoreDiff))"
    }
}
```

В `ios/SmartGolfCaddy/App/RootView.swift` — заменить целиком:

```swift
// ios/SmartGolfCaddy/App/RootView.swift
import GoogleSignIn
import SwiftUI

struct RootView: View {
    @State private var session = SessionViewModel()
    @State private var router = AppRouter()
    @State private var store = AppStore()

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ProgressView()
            case .signedOut:
                AuthView()
            case .signedIn:
                NavigationStack(path: $router.path) {
                    HomeView()
                        .navigationDestination(for: Route.self) { route in
                            destination(for: route)
                        }
                        .navigationBarHidden(true)
                }
            }
        }
        .environment(session)
        .environment(router)
        .environment(store)
        .task { session.start() }
        .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .roundSetup:
            RoundSetupView()
        case .hole(let roundId, let number):
            HoleTrackerView(roundId: roundId, holeNumber: number)
        case .results(let roundId):
            RoundResultsView(roundId: roundId)
        }
    }
}
```

Примечание для сборки Task 4: `RoundSetupView`/`HoleTrackerView`/`RoundResultsView` появляются в Tasks 5–7. Чтобы Task 4 собирался и был проверяем сам по себе, создай ВРЕМЕННЫЕ заглушки в `ios/SmartGolfCaddy/Views/` (по одному файлу, каждый — `struct X: View { let roundId/holeNumber…; var body: some View { Text("В разработке").font(DSFont.bodyMD) } }` с теми же сигнатурами, что в Produces следующих задач: `RoundSetupView()`, `HoleTrackerView(roundId: String, holeNumber: Int)`, `RoundResultsView(roundId: String)`). Tasks 5–7 заменяют содержимое этих файлов.

- [ ] **Step 4: Прогнать тесты — зелёные; запустить на симуляторе** (`./ios/scripts/build.sh`, установить, запустить — команды из Фазы 1). Expected: Home с градиентной шапкой «ДОБРО ПОЖАЛОВАТЬ, <имя>», кнопка «НАЧАТЬ НОВЫЙ РАУНД» → заглушка «В разработке»; назад — свайпом.

- [ ] **Step 5: Commit**

```bash
git add ios/SmartGolfCaddy/App ios/SmartGolfCaddy/ViewModels ios/SmartGolfCaddy/Views ios/SmartGolfCaddyTests/HomeViewModelTests.swift
git commit -m "feat(ios): navigation router + home screen with resume card"
```

---

### Task 5: Экран настройки раунда

**Files:**
- Modify: `ios/SmartGolfCaddy/Views/RoundSetupView.swift` (замена заглушки)
- Create: `ios/SmartGolfCaddy/ViewModels/RoundSetupViewModel.swift`

**Interfaces:**
- Consumes: `RoundsService.createSoloRound`, `AuthService.currentUserId`, `SessionViewModel.profile`, `TeeColor` + labels (Task 1), `AppRouter`, `DSButton`, `Color(hex:)`.
- Produces: `RoundSetupView()` (сигнатура уже в роутере). После создания раунда роутер делает `replaceLast(.hole(roundId:number:1))` — стек: Home → HoleTracker (Setup исчезает).

- [ ] **Step 1: Реализация**

```swift
// ios/SmartGolfCaddy/ViewModels/RoundSetupViewModel.swift
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
```

Замечание паритета: веб пишет в PlayerInfo email из Auth (для пост-раундового письма). В iOS email недоступен из AppUser; для соло-раунда авто-письмо шлётся на email из Auth-lookup сервера (бэкенд отрабатывает отсутствие email в PlayerInfo — задокументировано в CLAUDE.md веба). Оставляем nil осознанно.

```swift
// ios/SmartGolfCaddy/Views/RoundSetupView.swift — заменить заглушку целиком
import SwiftUI

struct RoundSetupView: View {
    @Environment(SessionViewModel.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var model = RoundSetupViewModel()
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                nameSection
                holesSection
                teeSection
                if let message = model.errorMessage {
                    Text(message)
                        .font(DSFont.labelLG)
                        .foregroundStyle(DSColor.error)
                        .frame(maxWidth: .infinity)
                }
                DSButton(title: model.creating ? "Создаём..." : "Начать раунд",
                         icon: "flag.fill",
                         disabled: model.creating) {
                    Task {
                        if let roundId = await model.createRound(profile: session.profile) {
                            router.replaceLast(.hole(roundId: roundId, number: 1))
                        }
                    }
                }
            }
            .padding(DS.screenPadding)
        }
        .background(DSColor.surface)
        .navigationTitle("Настройка раунда")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sectionHeader: (String) -> Text {
        { title in
            Text(title)
                .font(DSFont.labelLG)
                .tracking(1.2)
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("НАЗВАНИЕ ПОЛЯ")
                .foregroundStyle(DSColor.onSurfaceVariant)
            TextField("Например: Гольф клуб Москва", text: $model.courseName)
                .font(DSFont.bodyMD)
                .padding(14)
                .background(DSColor.surfaceContainerLowest)
                .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.cornerRadius)
                        .stroke(nameFocused ? DSColor.primary : DSColor.outlineVariant)
                )
                .focused($nameFocused)
        }
    }

    private var holesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("КОЛИЧЕСТВО ЛУНОК")
                .foregroundStyle(DSColor.onSurfaceVariant)
            HStack(spacing: 12) {
                ForEach([9, 18], id: \.self) { n in
                    Button {
                        model.totalHoles = n
                    } label: {
                        Text("\(n)")
                            .font(DSFont.titleLG)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: DS.touchTarget)
                    }
                    .background(model.totalHoles == n ? DSColor.primary : .clear)
                    .foregroundStyle(model.totalHoles == n ? DSColor.onPrimary : DSColor.onSurfaceVariant)
                    .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.cornerRadius)
                            .stroke(model.totalHoles == n ? DSColor.primary : DSColor.outlineVariant, lineWidth: 2)
                    )
                }
            }
        }
    }

    private var teeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("ТИИ (ОТКУДА ИГРАЕМ)")
                .foregroundStyle(DSColor.onSurfaceVariant)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(TeeColor.allCases, id: \.self) { tee in
                    teeCard(tee)
                }
            }
        }
    }

    private func teeCard(_ tee: TeeColor) -> some View {
        let selected = model.tee == tee
        return Button {
            model.tee = tee
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("T")
                    .font(DSFont.labelMD)
                    .foregroundStyle(Color(hex: tee.textHex))
                    .frame(width: 28, height: 28)
                    .background(Color(hex: tee.bgHex))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(DSColor.outlineVariant.opacity(0.4)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tee.label)
                        .font(DSFont.labelLG)
                        .foregroundStyle(DSColor.onSurface)
                    Text(tee.teeDescription)
                        .font(DSFont.labelMD)
                        .foregroundStyle(DSColor.onSurfaceVariant)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(12)
            .background(selected ? DSColor.primaryContainer.opacity(0.1) : DSColor.surfaceContainerLowest)
            .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DS.cornerRadius)
                    .stroke(selected ? DSColor.primary : DSColor.outlineVariant.opacity(0.6), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Собрать, прогнать все тесты, проверить на симуляторе**: Home → «Начать новый раунд» → форма (имя/9-18/тии) → «Начать раунд» → заглушка HoleTracker «В разработке» (Task 6 её заменит); в Firebase console → rounds появился документ со status active, holes по тии-множителю. Expected: `** TEST SUCCEEDED **`, документ корректен.

- [ ] **Step 3: Commit**

```bash
git add ios/SmartGolfCaddy/Views/RoundSetupView.swift ios/SmartGolfCaddy/ViewModels/RoundSetupViewModel.swift
git commit -m "feat(ios): round setup screen — course name, holes, tees"
```

---

### Task 6: Трекер лунок (соло) + редактор лунки

**Files:**
- Modify: `ios/SmartGolfCaddy/Views/HoleTrackerView.swift` (замена заглушки)
- Create: `ios/SmartGolfCaddy/ViewModels/HoleTrackerViewModel.swift`
- Create: `ios/SmartGolfCaddy/Views/Components/ClubChipView.swift`
- Create: `ios/SmartGolfCaddy/Views/HoleEditorSheet.swift`
- Test: `ios/SmartGolfCaddyTests/HoleTrackerViewModelTests.swift`

**Interfaces:**
- Consumes: `RoundsService.subscribeToRound/.finishRound/.updateHoleConfig`, `ShotQueue.shared` (recordShotQueued/pendingShot/pendingCount, .shotQueueDidChange), `AppStore.lastClubUsed`, `SessionViewModel.profile.resolvedBag`, `Clubs.label(for:in:)`, `TeeColor` labels, `Scoring` не нужен здесь.
- Produces: `HoleTrackerView(roundId: String, holeNumber: Int)`; `HoleTrackerViewModel` (описан ниже); `ClubChipView(label:selected:onTap:)`; `HoleEditorSheet(holeNumber:currentPar:currentDistance:saving:onSave:onCancel:)`.

**Ключевая логика (порт дословно из HoleTracker.tsx):** оптимистичный оверлей тегирован слотом `"\(holeIndex):\(uid)"` и `awaitingKey` (= clubs.join("|")); отображаемые клюшки деривятся: optimistic (пока сервер не отэхоил awaitingKey) → иначе pending из очереди → иначе server. Permanent-отказ → rollback оверлея этого слота + ошибка.

- [ ] **Step 1: Падающие тесты (дерив отображаемых клюшек)**

```swift
// ios/SmartGolfCaddyTests/HoleTrackerViewModelTests.swift
import XCTest
@testable import SmartGolfCaddy

final class HoleTrackerViewModelTests: XCTestCase {

    @MainActor
    func testDisplayedClubsPrefersOptimisticUntilServerEchoes() {
        let model = HoleTrackerViewModel(roundId: "r", holeIndex: 0, userId: "u")
        model.optimistic = .init(slot: "0:u", clubs: ["Driver", "7i"], awaitingKey: "Driver|7i")
        // Сервер ещё показывает старое (1 удар) — оверлей впереди
        XCTAssertEqual(model.displayedClubs(serverClubs: ["Driver"], pendingClubs: nil), ["Driver", "7i"])
        // Сервер отэхоил — оверлей перестаёт применяться
        XCTAssertEqual(model.displayedClubs(serverClubs: ["Driver", "7i"], pendingClubs: nil), ["Driver", "7i"])
    }

    @MainActor
    func testDisplayedClubsIgnoresForeignSlotOverlay() {
        let model = HoleTrackerViewModel(roundId: "r", holeIndex: 3, userId: "u")
        model.optimistic = .init(slot: "0:u", clubs: ["Driver", "7i"], awaitingKey: "Driver|7i")
        // Оверлей другого слота (лунка 0) не протекает в лунку 3
        XCTAssertEqual(model.displayedClubs(serverClubs: [], pendingClubs: nil), [])
    }

    @MainActor
    func testDisplayedClubsFallsBackToPendingQueue() {
        let model = HoleTrackerViewModel(roundId: "r", holeIndex: 0, userId: "u")
        XCTAssertEqual(model.displayedClubs(serverClubs: [], pendingClubs: ["PW"]), ["PW"])
    }
}
```

- [ ] **Step 2: Прогнать — падает компиляцией.**

- [ ] **Step 3: Реализация**

```swift
// ios/SmartGolfCaddy/ViewModels/HoleTrackerViewModel.swift
import Foundation
import Observation

@Observable
@MainActor
final class HoleTrackerViewModel {

    struct Optimistic: Equatable {
        var slot: String
        var clubs: [String]
        var awaitingKey: String
    }

    let roundId: String
    let holeIndex: Int
    let userId: String

    var round: Round?
    var loadError: String?
    var saveError: String?
    var saving = false
    var finishing = false
    var hasQueuedShots = false
    var optimistic: Optimistic?

    private var unsubscribe: (() -> Void)?
    private var queueObserver: NSObjectProtocol?

    init(roundId: String, holeIndex: Int, userId: String) {
        self.roundId = roundId
        self.holeIndex = holeIndex
        self.userId = userId
    }

    var slotKey: String { "\(holeIndex):\(userId)" }
    var hole: HoleConfig? {
        guard let round, round.holes.indices.contains(holeIndex) else { return nil }
        return round.holes[holeIndex]
    }
    var isHost: Bool { round?.hostId == userId }

    func start() {
        refreshQueueBadge()
        queueObserver = NotificationCenter.default.addObserver(
            forName: .shotQueueDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshQueueBadge() }
        }
        unsubscribe = RoundsService.subscribeToRound(
            roundId: roundId,
            onChange: { [weak self] round in self?.round = round },
            onError: { [weak self] _ in
                self?.loadError = "Не удалось загрузить раунд. Проверьте связь."
            }
        )
    }

    /// Дерив отображаемой серии (порт myClubs из HoleTracker.tsx):
    /// optimistic пока «впереди» сервера → pending из очереди → server.
    func displayedClubs(serverClubs: [String], pendingClubs: [String]?) -> [String] {
        if let optimistic, optimistic.slot == slotKey,
           serverClubs.joined(separator: "|") != optimistic.awaitingKey {
            return optimistic.clubs
        }
        return pendingClubs ?? serverClubs
    }

    var currentClubs: [String] {
        let server = hole?.shots[userId]?.resolvedClubs ?? []
        let pending = ShotQueue.shared.pendingShot(
            roundId: roundId, holeIndex: holeIndex, targetUid: userId
        )?.clubs
        return displayedClubs(serverClubs: server, pendingClubs: pending)
    }

    func save(_ clubs: [String]) async {
        saving = true
        saveError = nil
        optimistic = Optimistic(slot: slotKey, clubs: clubs,
                                awaitingKey: clubs.joined(separator: "|"))
        defer { saving = false }
        let outcome = await ShotQueue.shared.recordShotQueued(
            roundId: roundId, holeIndex: holeIndex, targetUid: userId, clubs: clubs
        )
        if case .rejected = outcome {
            saveError = "Не удалось сохранить удар."
            if optimistic?.slot == slotKey { optimistic = nil }  // rollback слота
        }
        refreshQueueBadge()
    }

    func finish() async -> Bool {
        guard !finishing else { return false }
        finishing = true
        saveError = nil
        defer { finishing = false }
        do {
            try await RoundsService.finishRound(roundId: roundId)
            return true
        } catch {
            saveError = "Не удалось завершить раунд. Попробуйте ещё раз."
            return false
        }
    }

    func saveHoleConfig(par: Int?, distanceMeters: Int?) async -> Bool {
        do {
            try await RoundsService.updateHoleConfig(
                roundId: roundId, holeIndex: holeIndex,
                par: par, distanceMeters: distanceMeters
            )
            return true
        } catch {
            saveError = "Не удалось сохранить параметры лунки."
            return false
        }
    }

    private func refreshQueueBadge() {
        hasQueuedShots = ShotQueue.shared.pendingCount(roundId: roundId) > 0
    }

    @MainActor deinit {
        unsubscribe?()
        if let queueObserver { NotificationCenter.default.removeObserver(queueObserver) }
    }
}
```

```swift
// ios/SmartGolfCaddy/Views/Components/ClubChipView.swift
import SwiftUI

struct ClubChipView: View {
    let label: String
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(DSFont.labelLG)
                .padding(.horizontal, 16)
                .frame(minHeight: DS.touchTarget)
        }
        .background(selected ? DSColor.primary : DSColor.surfaceContainerLowest)
        .foregroundStyle(selected ? DSColor.onPrimary : DSColor.onSurface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(selected ? DSColor.primary : DSColor.outlineVariant.opacity(0.6)))
    }
}
```

```swift
// ios/SmartGolfCaddy/Views/HoleEditorSheet.swift
// Порт HoleEditorDialog: par 3/4/5 кнопками, дистанция 50–700 м.
import SwiftUI

struct HoleEditorSheet: View {
    let holeNumber: Int
    let currentPar: Int
    let currentDistance: Int
    let saving: Bool
    let onSave: (_ par: Int?, _ distanceMeters: Int?) -> Void
    let onCancel: () -> Void

    @State private var par: Int
    @State private var distanceText: String
    @State private var validationError: String?

    init(holeNumber: Int, currentPar: Int, currentDistance: Int, saving: Bool,
         onSave: @escaping (Int?, Int?) -> Void, onCancel: @escaping () -> Void) {
        self.holeNumber = holeNumber
        self.currentPar = currentPar
        self.currentDistance = currentDistance
        self.saving = saving
        self.onSave = onSave
        self.onCancel = onCancel
        _par = State(initialValue: currentPar)
        _distanceText = State(initialValue: String(currentDistance))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Параметры лунки \(holeNumber)")
                    .font(DSFont.titleLG)
                    .foregroundStyle(DSColor.onSurface)
                Text("Подгоните под реальное поле — изменение видно всем игрокам.")
                    .font(DSFont.labelMD)
                    .foregroundStyle(DSColor.onSurfaceVariant)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("ПАР")
                    .font(DSFont.labelMD)
                    .tracking(1.2)
                    .foregroundStyle(DSColor.onSurfaceVariant)
                HStack(spacing: 8) {
                    ForEach([3, 4, 5], id: \.self) { value in
                        Button {
                            par = value
                        } label: {
                            Text("\(value)")
                                .font(DSFont.displayLG)
                                .frame(maxWidth: .infinity, minHeight: 64)
                        }
                        .background(par == value ? DSColor.primary : DSColor.surfaceContainerLowest)
                        .foregroundStyle(par == value ? DSColor.onPrimary : DSColor.onSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(par == value ? DSColor.primary : DSColor.outlineVariant, lineWidth: 2)
                        )
                        .disabled(saving)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("ДИСТАНЦИЯ, МЕТРОВ")
                    .font(DSFont.labelMD)
                    .tracking(1.2)
                    .foregroundStyle(DSColor.onSurfaceVariant)
                TextField("", text: $distanceText)
                    .keyboardType(.numberPad)
                    .font(DSFont.headlineMD)
                    .monospacedDigit()
                    .padding(14)
                    .background(DSColor.surfaceContainerLow)
                    .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
                    .disabled(saving)
                if let validationError {
                    Text(validationError)
                        .font(DSFont.labelMD)
                        .foregroundStyle(DSColor.error)
                }
            }

            HStack(spacing: 8) {
                DSButton(title: "Отмена", style: .secondary, disabled: saving, action: onCancel)
                DSButton(title: saving ? "Сохраняем..." : "Сохранить", disabled: saving) {
                    submit()
                }
            }
        }
        .padding(20)
        .presentationDetents([.medium])
    }

    private func submit() {
        guard let parsed = Int(distanceText), (50...700).contains(parsed) else {
            validationError = "Дистанция должна быть 50–700 метров"
            return
        }
        validationError = nil
        let parPatch: Int? = par != currentPar ? par : nil
        let distPatch: Int? = parsed != currentDistance ? parsed : nil
        if parPatch == nil && distPatch == nil {
            onCancel()
            return
        }
        onSave(parPatch, distPatch)
    }
}
```

```swift
// ios/SmartGolfCaddy/Views/HoleTrackerView.swift — заменить заглушку целиком
import SwiftUI

struct HoleTrackerView: View {
    let roundId: String
    let holeNumber: Int

    @Environment(SessionViewModel.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(AppStore.self) private var store
    @State private var model: HoleTrackerViewModel
    @State private var selectedClub: String = "Driver"
    @State private var showFinishConfirm = false
    @State private var showHoleEditor = false
    @State private var savingHole = false

    private let haptics = UIImpactFeedbackGenerator(style: .medium)

    init(roundId: String, holeNumber: Int) {
        self.roundId = roundId
        self.holeNumber = holeNumber
        _model = State(initialValue: HoleTrackerViewModel(
            roundId: roundId,
            holeIndex: holeNumber - 1,
            userId: AuthService.currentUserId ?? ""
        ))
    }

    private var pickerClubs: [BagClub] {
        let enabled = (session.profile?.resolvedBag ?? Clubs.defaultBag).filter(\.enabled)
        return enabled.isEmpty ? Clubs.defaultBag : enabled
    }

    private var fullBag: [BagClub] { session.profile?.resolvedBag ?? Clubs.defaultBag }

    var body: some View {
        Group {
            if let round = model.round, let hole = model.hole {
                content(round: round, hole: hole)
            } else if let loadError = model.loadError {
                VStack(spacing: 16) {
                    Text(loadError)
                        .font(DSFont.bodyMD)
                        .foregroundStyle(DSColor.error)
                        .multilineTextAlignment(.center)
                    DSButton(title: "На главную", style: .secondary) { router.popToRoot() }
                        .padding(.horizontal, 48)
                }
                .padding(DS.screenPadding)
            } else {
                ProgressView("Загрузка...")
            }
        }
        .background(DSColor.surface)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Лунка \(holeNumber) / \(model.round?.totalHoles ?? 0)")
                    .font(DSFont.titleLG)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    router.popToRoot()
                } label: {
                    Image(systemName: "house")
                }
                .accessibilityLabel("На главную")
            }
        }
        .task {
            selectedClub = store.lastClubUsed
            model.start()
        }
        .onChange(of: model.round?.status) { _, status in
            if status == .finished {
                router.replaceLast(.results(roundId: roundId))
            }
        }
        .confirmationDialog("Закончить игру?", isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button("Завершить", role: .destructive) {
                Task {
                    if await model.finish() {
                        router.replaceLast(.results(roundId: roundId))
                    }
                }
            }
            Button("Продолжить", role: .cancel) {}
        } message: {
            Text(finishConfirmBody)
        }
        .sheet(isPresented: $showHoleEditor) {
            if let hole = model.hole {
                HoleEditorSheet(
                    holeNumber: holeNumber,
                    currentPar: hole.par,
                    currentDistance: hole.distanceMeters,
                    saving: savingHole,
                    onSave: { par, dist in
                        Task {
                            savingHole = true
                            let ok = await model.saveHoleConfig(par: par, distanceMeters: dist)
                            savingHole = false
                            if ok { showHoleEditor = false }
                        }
                    },
                    onCancel: { if !savingHole { showHoleEditor = false } }
                )
            }
        }
    }

    private var finishConfirmBody: String {
        guard let round = model.round else { return "" }
        if holeNumber < round.totalHoles {
            return "Вы прошли \(holeNumber - 1) из \(round.totalHoles) лунок. Пройденные удары попадут в итоги, незавершённые лунки — без ударов."
        }
        return "Раунд будет записан в историю. Изменить удары после этого нельзя."
    }

    @ViewBuilder
    private func content(round: Round, hole: HoleConfig) -> some View {
        VStack(spacing: 0) {
            holeHeader(round: round, hole: hole)
            ScrollView {
                VStack(spacing: 24) {
                    counter
                    if !model.currentClubs.isEmpty { series }
                    if let saveError = model.saveError {
                        Text(saveError)
                            .font(DSFont.labelLG)
                            .foregroundStyle(DSColor.error)
                    }
                    if model.hasQueuedShots {
                        Label("Нет сети — удары сохранятся автоматически", systemImage: "wifi.slash")
                            .font(DSFont.labelMD)
                            .foregroundStyle(DSColor.onSurfaceVariant)
                    }
                    clubPicker
                }
                .padding(.vertical, 16)
            }
            navigationButtons(round: round)
        }
    }

    private func holeHeader(round: Round, hole: HoleConfig) -> some View {
        HStack {
            Button {
                if model.isHost { showHoleEditor = true }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ПАР")
                        .font(DSFont.labelLG)
                        .foregroundStyle(DSColor.onPrimary.opacity(0.7))
                    Text("\(hole.par)")
                        .font(DSFont.headlineMD)
                        .foregroundStyle(DSColor.onPrimary)
                        .underline(model.isHost, pattern: .dot)
                }
            }
            .disabled(!model.isHost)
            Spacer()
            Text("\(holeNumber)")
                .font(DSFont.displayLG)
                .foregroundStyle(DSColor.onPrimary)
            Spacer()
            Button {
                if model.isHost { showHoleEditor = true }
            } label: {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ДИСТ.")
                        .font(DSFont.labelLG)
                        .foregroundStyle(DSColor.onPrimary.opacity(0.7))
                    HStack(spacing: 6) {
                        Text("\(hole.distanceMeters) м")
                            .font(DSFont.headlineMD)
                            .foregroundStyle(DSColor.onPrimary)
                            .underline(model.isHost, pattern: .dot)
                        Circle()
                            .fill(Color(hex: round.tee.bgHex))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(DSColor.onPrimary.opacity(0.3)))
                            .accessibilityLabel("Тии: \(round.tee.label)")
                    }
                }
            }
            .disabled(!model.isHost)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(DSColor.primaryContainer)
    }

    private var counter: some View {
        VStack(spacing: 12) {
            Text("ВАШИ УДАРЫ")
                .font(DSFont.labelLG)
                .tracking(1.5)
                .foregroundStyle(DSColor.onSurfaceVariant)
            HStack(spacing: 40) {
                Button {
                    haptics.impactOccurred()
                    let clubs = model.currentClubs
                    guard !clubs.isEmpty else { return }
                    Task { await model.save(Array(clubs.dropLast())) }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 28, weight: .bold))
                        .frame(width: 64, height: 64)
                }
                .background(.clear)
                .foregroundStyle(DSColor.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DSColor.primary, lineWidth: 2))
                .disabled(model.currentClubs.isEmpty || model.saving)
                .opacity(model.currentClubs.isEmpty || model.saving ? 0.3 : 1)

                Text("\(model.currentClubs.count)")
                    .font(DSFont.bold(64))
                    .foregroundStyle(DSColor.primary)
                    .monospacedDigit()
                    .frame(minWidth: 80)

                Button {
                    haptics.impactOccurred()
                    Task {
                        await model.save(model.currentClubs + [selectedClub])
                        store.lastClubUsed = selectedClub
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .bold))
                        .frame(width: 64, height: 64)
                }
                .background(DSColor.primary)
                .foregroundStyle(DSColor.onPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .disabled(model.saving)
                .opacity(model.saving ? 0.3 : 1)
            }
            Text("УДАРЫ")
                .font(DSFont.labelMD)
                .tracking(3)
                .foregroundStyle(DSColor.onSurfaceVariant)
        }
    }

    private var series: some View {
        VStack(spacing: 6) {
            Text("Серия ударов")
                .font(DSFont.labelMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
            FlowLayoutCompat(items: Array(model.currentClubs.enumerated()), spacing: 6) { index, club in
                Text("\(index + 1). \(Clubs.label(for: club, in: fullBag))")
                    .font(DSFont.labelMD)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(DSColor.surfaceContainer)
                    .foregroundStyle(DSColor.onSurfaceVariant)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, DS.screenPadding)
        }
    }

    private var clubPicker: some View {
        VStack(spacing: 8) {
            Text("ВЫБОР КЛЮШКИ")
                .font(DSFont.labelLG)
                .tracking(1.5)
                .foregroundStyle(DSColor.onSurfaceVariant)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pickerClubs) { club in
                        ClubChipView(
                            label: Clubs.label(for: club.id, in: fullBag),
                            selected: selectedClub == club.id
                        ) {
                            selectedClub = club.id
                        }
                    }
                }
                .padding(.horizontal, DS.screenPadding)
            }
        }
        .onChange(of: pickerClubs.map(\.id)) { _, ids in
            if !ids.contains(selectedClub) { selectedClub = ids.first ?? "Driver" }
        }
    }

    private func navigationButtons(round: Round) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                DSButton(title: "Пред.", icon: "chevron.left", style: .secondary,
                         disabled: holeNumber == 1) {
                    router.replaceLast(.hole(roundId: roundId, number: holeNumber - 1))
                }
                if holeNumber < round.totalHoles {
                    DSButton(title: "Дальше", icon: "chevron.right") {
                        router.replaceLast(.hole(roundId: roundId, number: holeNumber + 1))
                    }
                } else {
                    DSButton(title: "Закончить игру", icon: "flag.fill",
                             disabled: model.finishing) {
                        showFinishConfirm = true
                    }
                }
            }
            if model.isHost && holeNumber < round.totalHoles {
                DSButton(title: "Закончить игру досрочно", icon: "flag", style: .secondary,
                         disabled: model.finishing) {
                    showFinishConfirm = true
                }
            }
        }
        .padding(.horizontal, DS.screenPadding)
        .padding(.bottom, 12)
    }
}

// Простейший flow-layout для чипов серии (перенос по строкам).
struct FlowLayoutCompat<Item, Content: View>: View {
    let items: [(offset: Int, element: Item)]
    let spacing: CGFloat
    @ViewBuilder let content: (Int, Item) -> Content

    init(items: [(offset: Int, element: Item)], spacing: CGFloat,
         @ViewBuilder content: @escaping (Int, Item) -> Content) {
        self.items = items
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        // LazyVGrid c adaptive-колонками даёт перенос чипов без ручной геометрии.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: spacing)], spacing: spacing) {
            ForEach(items, id: \.offset) { pair in
                content(pair.offset, pair.element)
            }
        }
    }
}
```

Замечания для исполнителя:
- Переключатель «Пред./Дальше» через `router.replaceLast` пересоздаёт HoleTrackerView с новым holeNumber (init → новая VM с новым holeIndex) — это ЗАДУМАНО: состояние лунки живёт в Firestore/очереди, VM пересоздаётся чистой (веб делает то же через URL-роут).
- `selectedClub` сбрасывается на `store.lastClubUsed` при каждом входе на лунку (в `.task`) — паритет с вебом.
- `MainActor.assumeIsolated` в обсервере — очередь .main гарантирует MainActor; если компилятор новой Xcode заругается, замени на `Task { @MainActor in self?.refreshQueueBadge() }`.

- [ ] **Step 4: Прогнать все тесты — зелёные; смоук на симуляторе:** Home → новый раунд → лунка 1: тапнуть «+» три раза (счётчик 3, серия «1. DRV 2. DRV 3. DRV» при дефолтной клюшке), «−» один раз (2), выбрать другую клюшку → «+» (серия оканчивается ей), «Дальше» → лунка 2, «Пред.» → лунка 1 (удары на месте — пришли с сервера), тап по «Пар» (вы — хост) → редактор: пар 5, дистанция 480 → «Сохранить» → шапка обновилась (сервер!), «Закончить игру досрочно» → диалог → «Завершить» → заглушка «В разработке» (Results, Task 7). В Firebase console: у раунда status finished, holes[0].shots заполнены.

- [ ] **Step 5: Commit**

```bash
git add ios/SmartGolfCaddy/Views ios/SmartGolfCaddy/ViewModels/HoleTrackerViewModel.swift ios/SmartGolfCaddyTests/HoleTrackerViewModelTests.swift
git commit -m "feat(ios): hole tracker — shots, clubs, optimistic UI, offline badge, hole editor"
```

---

### Task 7: Экран итогов раунда

**Files:**
- Modify: `ios/SmartGolfCaddy/Views/RoundResultsView.swift` (замена заглушки)
- Create: `ios/SmartGolfCaddy/ViewModels/RoundResultsViewModel.swift`

**Interfaces:**
- Consumes: `RoundsService.subscribeToRound`, `Scoring.playerTotals/.leaderboard/.clubUsage/.matchPlayStatus`, `Score.color/.onColor/.label`, `Clubs.label(for:in:)`, `SessionViewModel.profile.resolvedBag`, `pluralRu`, `AppRouter`.
- Produces: `RoundResultsView(roundId: String)`. Кнопка «Новый раунд» → `router.popToRoot()` затем `router.push(.roundSetup)`; «На главную» → `popToRoot()`.

- [ ] **Step 1: Реализация**

```swift
// ios/SmartGolfCaddy/ViewModels/RoundResultsViewModel.swift
import Foundation
import Observation

@Observable
@MainActor
final class RoundResultsViewModel {
    var round: Round?
    var loadError: String?
    private var unsubscribe: (() -> Void)?

    func start(roundId: String) {
        guard unsubscribe == nil else { return }
        unsubscribe = RoundsService.subscribeToRound(
            roundId: roundId,
            onChange: { [weak self] round in self?.round = round },
            onError: { [weak self] _ in
                self?.loadError = "Не удалось загрузить итоги. Проверьте связь."
            }
        )
    }

    @MainActor deinit {
        unsubscribe?()
    }
}
```

```swift
// ios/SmartGolfCaddy/Views/RoundResultsView.swift — заменить заглушку целиком
import SwiftUI

struct RoundResultsView: View {
    let roundId: String

    @Environment(SessionViewModel.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var model = RoundResultsViewModel()

    private var viewerBag: [BagClub] { session.profile?.resolvedBag ?? Clubs.defaultBag }

    var body: some View {
        Group {
            if let round = model.round {
                content(round)
            } else if let loadError = model.loadError {
                VStack(spacing: 16) {
                    Text(loadError)
                        .font(DSFont.bodyMD)
                        .foregroundStyle(DSColor.error)
                        .multilineTextAlignment(.center)
                    DSButton(title: "На главную", style: .secondary) { router.popToRoot() }
                        .padding(.horizontal, 48)
                }
                .padding(DS.screenPadding)
            } else {
                ProgressView("Загрузка результатов...")
            }
        }
        .background(DSColor.surface)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Итоги раунда").font(DSFont.titleLG)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button { router.popToRoot() } label: { Image(systemName: "house") }
                    .accessibilityLabel("На главную")
            }
        }
        .task { model.start(roundId: roundId) }
    }

    @ViewBuilder
    private func content(_ round: Round) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                hero(round)
                if round.playerIds.count > 1 { leaderboardSection(round) }
                clubUsageSection(round)
                scorecardSection(round)
                VStack(spacing: 10) {
                    DSButton(title: "Новый раунд", icon: "plus") {
                        router.popToRoot()
                        router.push(.roundSetup)
                    }
                    DSButton(title: "На главную", style: .secondary) { router.popToRoot() }
                }
                .padding(.horizontal, DS.screenPadding)
            }
            .padding(.bottom, 32)
        }
    }

    // Соло: свой результат; матч (2 игрока, match): статус; иначе — победитель.
    @ViewBuilder
    private func hero(_ round: Round) -> some View {
        let isSolo = round.playerIds.count == 1
        let isMatch = round.playMode == .match && round.playerIds.count == 2
        VStack(spacing: 8) {
            Image(systemName: isSolo ? "flag.fill" : "trophy.fill")
                .font(.system(size: 24))
                .foregroundStyle(DSColor.onPrimary)
                .frame(width: 48, height: 48)
                .background(DSColor.onPrimary.opacity(0.1))
                .clipShape(Circle())
            if isMatch {
                let status = Scoring.matchPlayStatus(round: round,
                                                     uidA: round.playerIds[0],
                                                     uidB: round.playerIds[1])
                Text("MATCH PLAY")
                    .font(DSFont.labelLG).tracking(2.5)
                    .foregroundStyle(DSColor.onPrimary.opacity(0.7))
                Text(status.label)
                    .font(DSFont.displayLG)
                    .foregroundStyle(DSColor.onPrimary)
                    .monospacedDigit()
                Text(status.leaderUid.flatMap { round.players[$0]?.name } ?? "Игроки на равных")
                    .font(DSFont.bodyMD)
                    .foregroundStyle(DSColor.onPrimary)
            } else if isSolo {
                let totals = Scoring.playerTotals(round: round, userId: round.playerIds[0])
                Text("ВАШ РЕЗУЛЬТАТ")
                    .font(DSFont.labelLG).tracking(2.5)
                    .foregroundStyle(DSColor.onPrimary.opacity(0.7))
                Text("\(totals.totalScore) уд.")
                    .font(DSFont.displayLG)
                    .foregroundStyle(DSColor.onPrimary)
                    .monospacedDigit()
                Text("\(totals.scoreDiff >= 0 ? "+" : "")\(totals.scoreDiff) (\(Score.label(totals.scoreDiff)))")
                    .font(DSFont.bodyMD)
                    .foregroundStyle(DSColor.onPrimary)
            } else {
                let winner = Scoring.leaderboard(round: round).first
                Text("ПОБЕДИТЕЛЬ")
                    .font(DSFont.labelLG).tracking(2.5)
                    .foregroundStyle(DSColor.onPrimary.opacity(0.7))
                Text((winner?.thru ?? 0) > 0 ? (winner?.name ?? "Неизвестно") : "Неизвестно")
                    .font(DSFont.headlineLG)
                    .foregroundStyle(DSColor.onPrimary)
            }
            Text("\(round.courseName) · \(round.totalHoles) \(pluralRu(round.totalHoles, "лунка", "лунки", "лунок"))")
                .font(DSFont.labelMD)
                .foregroundStyle(DSColor.onPrimary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            LinearGradient(colors: [DSColor.primaryContainer, DSColor.primary],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private func leaderboardSection(_ round: Round) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Таблица")
            ForEach(Scoring.leaderboard(round: round)) { entry in
                HStack {
                    Text(entry.name)
                        .font(DSFont.bodyMD)
                        .foregroundStyle(DSColor.onSurface)
                        .lineLimit(1)
                    Spacer()
                    Text("\(entry.totalScore)")
                        .font(DSFont.titleLG)
                        .foregroundStyle(DSColor.onSurface)
                        .monospacedDigit()
                    scorePill(delta: entry.scoreDiff)
                }
                .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, DS.screenPadding)
    }

    private func clubUsageSection(_ round: Round) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(round.playerIds, id: \.self) { uid in
                let usage = Scoring.clubUsage(round: round, userId: uid)
                if !usage.isEmpty {
                    sectionTitle(round.playerIds.count == 1
                                 ? "Клюшки"
                                 : "Клюшки · \(round.players[uid]?.name ?? "")")
                    FlowLayoutCompat(items: Array(usage.enumerated()), spacing: 6) { _, stat in
                        Text("\(Clubs.label(for: stat.club, in: viewerBag)) · \(stat.count) (\(stat.percent)%)")
                            .font(DSFont.labelMD)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(DSColor.surfaceContainer)
                            .foregroundStyle(DSColor.onSurfaceVariant)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, DS.screenPadding)
    }

    // Скоркарта: горизонтальный скролл, ячейка лунки закрашена scoreColor.
    private func scorecardSection(_ round: Round) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Скоркарта")
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        cell("Лунка", width: 72, header: true)
                        ForEach(round.holes, id: \.holeNumber) { hole in
                            cell("\(hole.holeNumber)", header: true)
                        }
                    }
                    HStack(spacing: 4) {
                        cell("Пар", width: 72, header: true)
                        ForEach(round.holes, id: \.holeNumber) { hole in
                            cell("\(hole.par)")
                        }
                    }
                    ForEach(round.playerIds, id: \.self) { uid in
                        HStack(spacing: 4) {
                            cell(round.playerIds.count == 1 ? "Удары" : (round.players[uid]?.name ?? ""), width: 72, header: true)
                            ForEach(round.holes, id: \.holeNumber) { hole in
                                let shots = hole.shots[uid]?.count ?? 0
                                if shots > 0 {
                                    cell("\(shots)",
                                         background: Color(hex: Score.color(shots - hole.par)),
                                         foreground: Color(hex: Score.onColor(shots - hole.par)))
                                } else {
                                    cell("—")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.screenPadding)
            }
        }
    }

    private func cell(_ text: String, width: CGFloat = 36,
                      header: Bool = false,
                      background: Color = .clear,
                      foreground: Color? = nil) -> some View {
        Text(text)
            .font(header ? DSFont.labelMD : DSFont.labelLG)
            .monospacedDigit()
            .lineLimit(1)
            .frame(width: width, height: 32)
            .background(background)
            .foregroundStyle(foreground ?? (header ? DSColor.onSurfaceVariant : DSColor.onSurface))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func scorePill(delta: Int) -> some View {
        Text("\(delta >= 0 ? "+" : "")\(delta) (\(Score.label(delta)))")
            .font(DSFont.labelMD)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(delta == 0 ? Color.clear : Color(hex: Score.color(delta)))
            .foregroundStyle(delta == 0 ? DSColor.onSurface : Color(hex: Score.onColor(delta)))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(delta == 0 ? DSColor.outlineVariant : .clear))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(DSFont.titleLG)
            .foregroundStyle(DSColor.onSurface)
    }
}
```

- [ ] **Step 2: Прогнать все тесты + смоук:** завершённый раунд из Task 6 → Home → «Последние раунды» → карточка → итоги: hero «ВАШ РЕЗУЛЬТАТ N уд.», клюшки с процентами, скоркарта с цветными ячейками (birdie тёмно-зелёная с белым текстом, пар — белая с тёмным), «Новый раунд» → Настройка. Expected: `** TEST SUCCEEDED **` + визуальная проверка (скриншот в отчёт).

- [ ] **Step 3: Commit**

```bash
git add ios/SmartGolfCaddy/Views/RoundResultsView.swift ios/SmartGolfCaddy/ViewModels/RoundResultsViewModel.swift
git commit -m "feat(ios): round results — hero, club usage, colored scorecard"
```

---

### Task 8: Сквозной смоук соло-раунда + документация

**Files:**
- Modify: `CLAUDE.md` (описание слоёв iOS: экраны/роутер/очередь — 5-8 строк в существующую iOS-прозу)
- Возможные мелкие фиксы по результатам смоука (каждый — отдельным коммитом с префиксом `fix(ios):`)

**Interfaces:**
- Consumes: всё выше.
- Produces: подтверждённый сквозной соло-флоу на симуляторе + обновлённая документация.

- [ ] **Step 1: Полный прогон тестов** — `./ios/scripts/test.sh` → `** TEST SUCCEEDED **`, счётчик тестов вырос против Фазы 1 (26 + новые).

- [ ] **Step 2: Сквозной смоук на симуляторе** (`./ios/scripts/build.sh` + установка + запуск, команды Фазы 1):
1. Home: карточка «Продолжить раунд» отсутствует (если нет активного).
2. Новый раунд: имя «Тестовое поле», 9 лунок, тии женские → создать.
3. Лунка 1: 4 удара разными клюшками; лунка 2: 3 удара; вернуться на лунку 1 — серия на месте.
4. Убить приложение (`xcrun simctl terminate booted com.dzhambulat.smartgolfcaddy`), запустить заново → Home показывает «Продолжить раунд · Пройдено 2 из 9» → тап → открылась лунка 3 (первая несыгранная).
5. Пар-редактор на лунке 3: пар 3, дистанция 120 → сохранить → шапка обновилась.
6. «Закончить игру досрочно» → подтвердить → Итоги: результат, клюшки, скоркарта (лунки 3-9 «—»).
7. «Новый раунд» → Настройка → назад (свайп/«домой»).
8. Home: завершённый раунд появился в «Последние раунды» с очками.
Скриншоты ключевых экранов — в отчёт. Любой дефект — чинить немедленно (fix-коммиты), повторять смоук.

- [ ] **Step 3: Смоук офлайн-очереди (симулятор):** очередь неюнит-тестируемую часть (NWPathMonitor) проверяем так: в активном раунде включить в macOS «переключить Wi-Fi выкл» НЕЛЬЗЯ трогать (сеть хоста); вместо этого проверка ограничивается юнит-тестами Task 3 + бейджем: удостовериться, что при живой сети бейдж «Нет сети…» НЕ показывается. Полная офлайн-проверка — на iPhone пользователя (авиарежим) в приёмке фазы; отметить это в отчёте как ручной user-side шаг (контроллеру: авиарежим-тест провести при приёмке фазы на iPhone).

- [ ] **Step 4: Обновить CLAUDE.md** — в iOS-прозу (после абзаца про контракты) добавить:

```markdown
Фаза 2a: роутер `App/AppRouter.swift` (NavigationStack, enum Route);
экраны Home/RoundSetup/HoleTracker/RoundResults + вью-модели;
`Services/RoundsService.swift` (создание соло-раунда клиентом, finish,
подписка, запрос истории; удары/пар — через callable);
`Services/ShotQueue.swift` — офлайн-очередь ударов (файл в Application
Support, last-write-wins на слот `round:hole:uid`, флаш по
NWPathMonitor; смотри юнит-тесты как спецификацию). Скоринг —
`Models/Scoring.swift` (чистый порт scoring.ts).
```

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: phase 2a solo round — architecture notes"
```
