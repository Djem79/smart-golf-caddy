# iOS Phase 3a — Group Play & Match Play Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iOS получает групповую игру в полном объёме веб-версии: создание группового раунда, лобби с кодом и QR, вход по коду (включая deep-link), живая таблица во время игры, переключение игроков в трекере (хост ведёт счёт за всех), режим match play с ведением по лункам.

**Architecture:** Всё серверное уже готово и задеплоено (`joinLobbyByCode`, `startRound`/LEAVE-правила, `recordShot` с `targetUid`, движок `Scoring.matchPlayStatus`). Портируем клиент: три новых экрана (лобби, вход по коду, таблица) + расширение RoundSetup (режим Соло/Группа, формат Stroke/Match) + переключатель игроков в трекере. Роутер получает три новых маршрута; deep-link `smartgolfcaddy://join/<CODE>` обрабатывается в RootView.

**Tech Stack:** SwiftUI, FirebaseFirestore (подписки), CoreImage (генерация QR — без сторонних зависимостей).

**Spec:** `docs/superpowers/specs/2026-08-17-ios-app-design.md`. Веб-эталоны (source of truth поведения): `src/screens/GroupLobby.tsx`, `src/screens/JoinGame.tsx`, `src/screens/Leaderboard.tsx`, `src/screens/RoundSetup.tsx` (режимы), `src/screens/HoleTracker.tsx` (переключатель игроков), `src/services/rounds.ts`.

## Global Constraints

- Сборка/тесты ТОЛЬКО `./ios/scripts/test.sh` / `./ios/scripts/build.sh`; тест-таргет без Firebase/CoreLocation-импортов.
- `import Firebase*` — только `Services/*.swift` (+AppDelegate, DEBUG DiagnosticsView); `import CoreLocation` — только GeolocationService/ShotRangefinder.
- Каждая VM с подпиской: onError → видимая ошибка + escape; отписка в `@MainActor deinit`; `start()` идемпотентен (`guard unsubscribe == nil`).
- Русский UI дословно из плана; SF Symbols; ≥48pt; фиксированные шрифты; светлая тема уже форсирована.
- **Инвариант навигации:** каждый `navigationDestination` рендерится с `.id(route)` (урок Фазы 2а — иначе @State переживает смену маршрута).
- **Правила Firestore (после security-фикса):** клиент пишет только LEAVE (равенство множеств: новый playerIds = старый минус свой uid), START/FINISH (только хост). `players`/`holes` — server-only. Join — ТОЛЬКО через callable. Любая клиентская попытка иного — permission-denied.
- Match play осмыслен только при `playerIds.count == 2` (веб-паритет).
- Коммит после каждой задачи; сообщения — из задач.
- Доступные интерфейсы: `Round/PlayerInfo/HoleConfig/HoleShots`, `Scoring.*` (leaderboard/matchPlayStatus/playerTotals), `Score.*`, `Clubs.*`, `RoundsService`, `ShotQueue`, `ShotRangefinder`, `AppRouter/AppTab/Route`, `AppStore`, `SessionViewModel`, `AuthService`, `DSButton/DSColor/DSFont/DS`, `pluralRu`, `FlowLayoutCompat`, `ClubChipView`.

---

### Task 1: Сервисные операции группы (TDD-часть — чистые хелперы)

**Files:**
- Modify: `ios/SmartGolfCaddy/Services/RoundsService.swift` (createGroupRound, joinByCode, startRound, leaveLobby)
- Modify: `ios/SmartGolfCaddy/Services/CallableContracts.swift` (JoinLobbyPlayerInfo уже есть — проверить поля)
- Test: `ios/SmartGolfCaddyTests/RoundsServiceTests.swift` (+2: нормализация кода, форма документа группового раунда)

**Interfaces:**
- Produces:
  - `RoundsService.createGroupRound(hostId:hostInfo:courseId:courseName:totalHoles:tee:playMode:) async throws -> String` — status `lobby`, `startedAt: NSNull()`, playMode из аргумента
  - `RoundsService.joinByCode(_ code: String, playerInfo: PlayerInfo) async throws -> String?` — вызывает callable `joinLobbyByCode`, возвращает roundId или nil (лобби не найдено)
  - `RoundsService.startRound(roundId:) async throws` — updateData(status: active, startedAt: serverTimestamp)
  - `RoundsService.leaveLobby(roundId:userId:currentPlayerIds:) async throws` — пишет playerIds = current минус userId (правила требуют точного множества; поэтому передаём актуальный список из подписки, а не FieldValue.arrayRemove)
  - `Rounds.normalizeLobbyCode(_ raw: String) -> String` — только A-Z0-9, uppercase, обрезка до 6

- [ ] **Step 1: Падающие тесты**

```swift
    func testNormalizeLobbyCode() {
        XCTAssertEqual(Rounds.normalizeLobbyCode(" ab-c2 3d"), "ABC23D")
        XCTAssertEqual(Rounds.normalizeLobbyCode("abcdefgh"), "ABCDEF")   // обрезка до 6
        XCTAssertEqual(Rounds.normalizeLobbyCode("!!!"), "")
    }

    func testGroupRoundDocumentShape() {
        // Чистая проверка формы через хелпер, который собирает payload
        let payload = Rounds.groupRoundPayload(
            hostId: "u1",
            hostInfo: PlayerInfo(name: "А", avatar: "", totalScore: 0, scoreDiff: 0, email: nil),
            courseId: "c1", courseName: "Поле", totalHoles: 9, tee: .men, playMode: .match
        )
        XCTAssertEqual(payload["status"] as? String, "lobby")
        XCTAssertEqual(payload["playMode"] as? String, "match")
        XCTAssertEqual((payload["playerIds"] as? [String]) ?? [], ["u1"])
        XCTAssertTrue(payload["startedAt"] is NSNull)
        XCTAssertEqual((payload["holes"] as? [[String: Any]])?.count, 9)
        XCTAssertEqual((payload["lobbyCode"] as? String)?.count, 6)
    }
```

- [ ] **Step 2: RED.**

- [ ] **Step 3: Реализация**

В `enum Rounds` добавить:

```swift
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
```

В `RoundsService`:

```swift
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
```

- [ ] **Step 4: GREEN + build.**

- [ ] **Step 5: Commit** — `feat(ios): group round service ops — create lobby, join by code, start, leave`

---

### Task 2: Роутер, режимы в настройке раунда

**Files:**
- Modify: `ios/SmartGolfCaddy/App/AppRouter.swift` (+3 маршрута)
- Modify: `ios/SmartGolfCaddy/App/RootView.swift` (destination + deep-link)
- Modify: `ios/SmartGolfCaddy/ViewModels/RoundSetupViewModel.swift` (mode/playMode + createRound-ветка)
- Modify: `ios/SmartGolfCaddy/Views/RoundSetupView.swift` (секции «Режим игры» и «Формат игры»)
- Modify: `ios/SmartGolfCaddy/Views/HomeView.swift` (кнопка «Присоединиться к игре»)
- Create: заглушки `Views/GroupLobbyView.swift`, `Views/JoinGameView.swift`, `Views/LeaderboardView.swift` (T3–T5 заменят)
- Modify: `ios/project.yml` (URL scheme для deep-link)

**Interfaces:**
- Produces: `Route.lobby(roundId:)`, `Route.joinGame(code: String?)`, `Route.leaderboard(roundId:)`; `RoundSetupViewModel.mode: RoundMode` (`enum RoundMode { case solo, group }`), `.playMode: PlayMode`; `GroupLobbyView(roundId:)`, `JoinGameView(code: String?)`, `LeaderboardView(roundId:)`.

- [ ] **Step 1: Роутер и маршруты**

В `Route` добавить:

```swift
    case lobby(roundId: String)
    case joinGame(code: String?)
    case leaderboard(roundId: String)
```

В `RouteDestinationView` — соответствующие ветки (`GroupLobbyView(roundId:)`, `JoinGameView(code:)`, `LeaderboardView(roundId:)`).

- [ ] **Step 2: Deep-link**

`ios/project.yml` — в `CFBundleURLTypes` ДОБАВИТЬ вторую схему (не трогая существующую google-схему):

```yaml
          - CFBundleURLSchemes: ["smartgolfcaddy"]
```

`RootView.onOpenURL` — расширить: сначала пробуем разобрать join-ссылку, иначе отдаём GoogleSignIn:

```swift
        .onOpenURL { url in
            // smartgolfcaddy://join/ABC234 или https://<host>/join/ABC234
            if let code = Self.joinCode(from: url) {
                router.selectedTab = .rounds
                router.path = [.joinGame(code: code)]
                return
            }
            GIDSignIn.sharedInstance.handle(url)
        }
```

и статический хелпер в RootView:

```swift
    /// Извлекает код лобби из join-ссылки (схема приложения или веб-ссылка).
    static func joinCode(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        if url.scheme == "smartgolfcaddy", url.host == "join", let code = parts.first {
            return code
        }
        if parts.count >= 2, parts[parts.count - 2] == "join" {
            return parts[parts.count - 1]
        }
        return nil
    }
```

- [ ] **Step 3: Режимы в настройке раунда**

`RoundSetupViewModel`: добавить

```swift
enum RoundMode: String, CaseIterable {
    case solo, group
}
```

и поля `var mode: RoundMode = .solo`, `var playMode: PlayMode = .stroke`; в `createRound(profile:)` разветвить:

```swift
        // Match play осмыслен только вдвоём — соло-раунд всегда stroke
        // (веб-паритет createRound).
        let effectivePlayMode: PlayMode = mode == .group ? playMode : .stroke
        do {
            if mode == .group {
                return try await RoundsService.createGroupRound(
                    hostId: uid, hostInfo: info,
                    courseId: courseId, courseName: effectiveName,
                    totalHoles: totalHoles, tee: tee, playMode: effectivePlayMode
                )
            }
            return try await RoundsService.createSoloRound(...)   // существующий вызов
        } catch { ... }
```

`RoundSetupView`: две новые секции (после тии), карточки-выборы в стиле tee-карточек:

```swift
    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("РЕЖИМ ИГРЫ").foregroundStyle(DSColor.onSurfaceVariant)
            HStack(spacing: 12) {
                choiceCard(title: "Соло", subtitle: "Только вы",
                           icon: "person", selected: model.mode == .solo) { model.mode = .solo }
                choiceCard(title: "Группа", subtitle: "С друзьями",
                           icon: "person.2", selected: model.mode == .group) { model.mode = .group }
            }
            if model.mode == .group {
                Text("После создания раунда вы получите код, чтобы пригласить друзей")
                    .font(DSFont.labelMD)
                    .foregroundStyle(DSColor.onSurfaceVariant)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var formatSection: some View {
        if model.mode == .group {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("ФОРМАТ ИГРЫ").foregroundStyle(DSColor.onSurfaceVariant)
                HStack(spacing: 12) {
                    choiceCard(title: "Stroke", subtitle: "Общий счёт по ударам",
                               icon: "chart.bar", selected: model.playMode == .stroke) { model.playMode = .stroke }
                    choiceCard(title: "Match", subtitle: "2 игрока · по лункам",
                               icon: "flag.2.crossed", selected: model.playMode == .match) { model.playMode = .match }
                }
                if model.playMode == .match {
                    Text("Match play считается по победам в каждой лунке. Лучше всего работает 1 на 1.")
                        .font(DSFont.labelMD)
                        .foregroundStyle(DSColor.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func choiceCard(title: String, subtitle: String, icon: String,
                            selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? DSColor.primary : DSColor.onSurfaceVariant)
                Text(title).font(DSFont.labelLG).foregroundStyle(DSColor.onSurface)
                Text(subtitle).font(DSFont.labelMD).foregroundStyle(DSColor.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .padding(12)
            .background(selected ? DSColor.primaryContainer.opacity(0.1) : DSColor.surfaceContainerLowest)
            .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: DS.cornerRadius)
                .stroke(selected ? DSColor.primary : DSColor.outlineVariant.opacity(0.6), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
```

Кнопка «Начать раунд» в групповом режиме ведёт в лобби:

```swift
                    Task {
                        if let roundId = await model.createRound(profile: session.profile) {
                            router.replaceLast(model.mode == .group
                                               ? .lobby(roundId: roundId)
                                               : .hole(roundId: roundId, number: 1))
                        }
                    }
```

`HomeView` — третья кнопка под существующими:

```swift
                    DSButton(title: "Присоединиться к игре", icon: "person.2", style: .secondary) {
                        router.push(.joinGame(code: nil))
                    }
```

- [ ] **Step 4: Сборка + тесты + скриншот настройки раунда** (видны секции «Режим игры» и при выборе «Группа» — «Формат игры»).

- [ ] **Step 5: Commit** — `feat(ios): group/match modes in setup, join route, deep link`

---

### Task 3: Экран лобби (код, QR, игроки, старт)

**Files:**
- Create: `ios/SmartGolfCaddy/ViewModels/GroupLobbyViewModel.swift`
- Modify: `ios/SmartGolfCaddy/Views/GroupLobbyView.swift` (замена заглушки)
- Create: `ios/SmartGolfCaddy/Views/Components/QRCodeView.swift`
- Test: `ios/SmartGolfCaddyTests/QRCodeTests.swift`

**Interfaces:**
- Produces: `GroupLobbyView(roundId: String)`; `GroupLobbyViewModel` (`round`, `loadError`, `starting`, `errorMessage`, `start(roundId:)`, `startRound()`, `leave()`, `isHost`, `players`); `QRCodeView(text:size:)` + `QRCode.image(for:) -> UIImage?` (CoreImage, без внешних зависимостей).

- [ ] **Step 1: Падающий тест QR**

```swift
// ios/SmartGolfCaddyTests/QRCodeTests.swift
import XCTest
@testable import SmartGolfCaddy

final class QRCodeTests: XCTestCase {
    func testGeneratesImageForCode() throws {
        let image = try XCTUnwrap(QRCode.image(for: "smartgolfcaddy://join/ABC234"))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testEmptyStringGivesNil() {
        XCTAssertNil(QRCode.image(for: ""))
    }
}
```

- [ ] **Step 2: RED.**

- [ ] **Step 3: Реализация**

```swift
// ios/SmartGolfCaddy/Views/Components/QRCodeView.swift
// QR через CoreImage — без сторонних зависимостей (веб использует qrcode.react).
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

enum QRCode {
    static func image(for text: String) -> UIImage? {
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        // Апскейл до читаемого размера: нативный вывод ~25x25 точек.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct QRCodeView: View {
    let text: String
    var size: CGFloat = 200

    var body: some View {
        if let image = QRCode.image(for: text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel("QR-код для входа в лобби")
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}
```

```swift
// ios/SmartGolfCaddy/ViewModels/GroupLobbyViewModel.swift
import Foundation
import Observation

@Observable
@MainActor
final class GroupLobbyViewModel {
    var round: Round?
    var loadError: String?
    var errorMessage: String?
    var starting = false

    private var unsubscribe: (() -> Void)?

    var isHost: Bool {
        guard let round, let uid = AuthService.currentUserId else { return false }
        return round.hostId == uid
    }

    /// Участники в порядке playerIds (тот, кого нет в players-мапе, пропускается).
    var players: [(uid: String, info: PlayerInfo)] {
        guard let round else { return [] }
        return round.playerIds.compactMap { uid in
            round.players[uid].map { (uid, $0) }
        }
    }

    func start(roundId: String) {
        guard unsubscribe == nil else { return }
        unsubscribe = RoundsService.subscribeToRound(
            roundId: roundId,
            onChange: { [weak self] round in self?.round = round },
            onError: { [weak self] _ in
                self?.loadError = "Не удалось загрузить лобби. Возможно, вы не участник этого раунда или пропала связь."
            }
        )
    }

    func startRound(roundId: String) async {
        guard isHost, !starting else { return }
        starting = true
        errorMessage = nil
        defer { starting = false }
        do {
            try await RoundsService.startRound(roundId: roundId)
            // Подписка сама переведёт всех на лунку 1 при status == .active
        } catch {
            errorMessage = "Не удалось запустить раунд. Попробуйте ещё раз."
        }
    }

    func leave(roundId: String) async {
        guard let uid = AuthService.currentUserId, let round else { return }
        try? await RoundsService.leaveLobby(
            roundId: roundId, userId: uid, currentPlayerIds: round.playerIds
        )
    }

    @MainActor deinit {
        unsubscribe?()
    }
}
```

`GroupLobbyView` — экран по образцу веба: заголовок (поле · лунки), карточка кода (тап = копировать, «Скопировано»), карточка QR (`smartgolfcaddy://join/<CODE>`) с кнопкой «Скопировать ссылку», список игроков (аватар-заглушка SF Symbol, имя, бейдж «Хост»/«Вы»), внизу для хоста `DSButton("Начать раунд (N игроков)")` (disabled при starting), для остальных текст «Ожидаем хоста...», и «Покинуть лобби» (confirmationDialog с текстами веба: для хоста «Вы хост — без вас раунд не запустится...», иначе «Вы выйдете из этого лобби. Можно вернуться по коду.»).

Навигация по статусу:

```swift
        .onChange(of: model.round?.status) { _, status in
            guard let status else { return }
            if status == .active {
                router.replaceLast(.hole(roundId: roundId, number: 1))
            } else if status == .finished {
                router.replaceLast(.results(roundId: roundId))
            }
        }
```

После успешного выхода — `router.goHome()`.

- [ ] **Step 4: GREEN + build + скриншот лобби** (создать групповой раунд на симуляторе: код, QR, себя в списке, кнопка старта).

- [ ] **Step 5: Commit** — `feat(ios): group lobby — code, QR, players, host start`

---

### Task 4: Вход по коду

**Files:**
- Create: `ios/SmartGolfCaddy/ViewModels/JoinGameViewModel.swift`
- Modify: `ios/SmartGolfCaddy/Views/JoinGameView.swift` (замена заглушки)
- Test: `ios/SmartGolfCaddyTests/JoinGameViewModelTests.swift`

**Interfaces:**
- Produces: `JoinGameView(code: String?)`; `JoinGameViewModel` (`code`, `loading`, `errorMessage`, `join(profile:) async -> String?`, `canSubmit: Bool`, `autoJoinIfNeeded(initial:profile:) async -> String?`).

**Логика (порт JoinGame.tsx):** ввод только A-Z0-9, максимум 6 (через `Rounds.normalizeLobbyCode`); кнопка активна при длине 6; deep-link-код автоджоинится ровно один раз (латч); ошибки дословно: «Код должен содержать 6 символов», «Лобби с таким кодом не найдено. Проверьте код или попросите хоста создать новое.», «Не удалось присоединиться. Проверьте интернет и попробуйте снова.»

- [ ] **Step 1: Падающие тесты**

```swift
// ios/SmartGolfCaddyTests/JoinGameViewModelTests.swift
import XCTest
@testable import SmartGolfCaddy

final class JoinGameViewModelTests: XCTestCase {

    @MainActor
    func testCodeNormalizationAndSubmitGate() {
        let model = JoinGameViewModel(joiner: { _, _ in nil })
        model.setCode(" ab-c2 ")
        XCTAssertEqual(model.code, "ABC2")
        XCTAssertFalse(model.canSubmit)
        model.setCode("abc234xyz")
        XCTAssertEqual(model.code, "ABC234")   // обрезано до 6
        XCTAssertTrue(model.canSubmit)
    }

    @MainActor
    func testJoinNotFoundShowsMessage() async {
        let model = JoinGameViewModel(joiner: { _, _ in nil })
        model.setCode("ABC234")
        let roundId = await model.join(profile: nil)
        XCTAssertNil(roundId)
        XCTAssertEqual(model.errorMessage,
                       "Лобби с таким кодом не найдено. Проверьте код или попросите хоста создать новое.")
    }

    @MainActor
    func testJoinSuccessReturnsRoundId() async {
        let model = JoinGameViewModel(joiner: { code, _ in code == "ABC234" ? "r1" : nil })
        model.setCode("abc234")
        let roundId = await model.join(profile: nil)
        XCTAssertEqual(roundId, "r1")
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testAutoJoinRunsOnce() async {
        var calls = 0
        let model = JoinGameViewModel(joiner: { _, _ in calls += 1; return "r1" })
        _ = await model.autoJoinIfNeeded(initial: "ABC234", profile: nil)
        _ = await model.autoJoinIfNeeded(initial: "ABC234", profile: nil)
        XCTAssertEqual(calls, 1)
    }
}
```

- [ ] **Step 2: RED.**

- [ ] **Step 3: Реализация**

```swift
// ios/SmartGolfCaddy/ViewModels/JoinGameViewModel.swift
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
```

`JoinGameView(code: String?)`: иконка «ticket» в скруглённом контейнере, заголовок «Введите код лобби», подпись «Хост в своём приложении видит 6-значный код или QR», крупное поле ввода (`.textCase(.uppercase)`, `.autocorrectionDisabled()`, `.textInputAutocapitalization(.characters)`, моноширинный трекинг), сообщение об ошибке, `DSButton("Присоединиться"/"Подключаемся...")` (disabled при `!canSubmit`), `DSButton("Отмена", .secondary)` → `router.goHome()`. При успехе — `router.replaceLast(.lobby(roundId:))`. `.task { if let joined = await model.autoJoinIfNeeded(initial: code, profile: session.profile) { router.replaceLast(.lobby(roundId: joined)) } }`.

- [ ] **Step 4: GREEN + build + скриншот экрана ввода кода.**

- [ ] **Step 5: Commit** — `feat(ios): join game by code with deep-link auto-join`

---

### Task 5: Живая таблица и переключатель игроков в трекере

**Files:**
- Create: `ios/SmartGolfCaddy/ViewModels/LeaderboardViewModel.swift`
- Modify: `ios/SmartGolfCaddy/Views/LeaderboardView.swift` (замена заглушки)
- Modify: `ios/SmartGolfCaddy/ViewModels/HoleTrackerViewModel.swift` (активный игрок)
- Modify: `ios/SmartGolfCaddy/Views/HoleTrackerView.swift` (переключатель + кнопка таблицы)
- Test: `ios/SmartGolfCaddyTests/HoleTrackerViewModelTests.swift` (+2)

**Interfaces:**
- Produces: `LeaderboardView(roundId:)`; `LeaderboardViewModel` (round/loadError/start/deinit); в `HoleTrackerViewModel`: `var activeUserId: String` (по умолчанию свой uid), `func setActiveUser(_:)`, все операции записи используют `activeUserId` вместо `userId`; `var canScoreForOthers: Bool` (`round?.hostId == userId`).

**Ключевое правило (сервер уже enforce'ит):** писать за другого может ТОЛЬКО хост. Переключатель показывается лишь при `round.playerIds.count > 1`; не-хосту — только свой слот.

**Слоты дальномера/очереди** переключаются вместе с игроком: ключи очереди и меток строятся из `activeUserId` (иначе замер хоста припишется товарищу — находка финального ревью Фазы 2в). GPS-замер выполняется ТОЛЬКО когда `activeUserId == userId` (свой удар); для чужого слота дистанции не пишутся (0).

- [ ] **Step 1: Падающие тесты**

```swift
    @MainActor
    func testSlotKeyFollowsActiveUser() {
        let model = HoleTrackerViewModel(roundId: "r", holeIndex: 2, userId: "host")
        XCTAssertEqual(model.slotKey, "2:host")
        model.setActiveUser("mate")
        XCTAssertEqual(model.slotKey, "2:mate")
    }

    @MainActor
    func testDistancesMeasuredOnlyForOwnSlot() {
        let model = HoleTrackerViewModel(roundId: "r", holeIndex: 0, userId: "host")
        XCTAssertTrue(model.measuresDistances)      // свой слот
        model.setActiveUser("mate")
        XCTAssertFalse(model.measuresDistances)     // чужой слот — координаты не мои
    }
```

- [ ] **Step 2: RED.**

- [ ] **Step 3: Реализация**

`HoleTrackerViewModel`: добавить `private(set) var activeUserId: String` (инициализируется `userId`), `func setActiveUser(_ uid: String) { activeUserId = uid; optimistic = nil }`, заменить `userId` на `activeUserId` в `slotKey`, `currentClubs`, `currentDistances`, `save`, `refreshQueueBadge` и вызовах rangefinder; добавить `var measuresDistances: Bool { activeUserId == userId }` и в `save` выполнять замер/`markShot` только при `measuresDistances`.

`LeaderboardViewModel` — по образцу RoundResultsViewModel (подписка + onError «Не удалось загрузить таблицу. Проверьте связь.» + deinit).

`LeaderboardView`: шапка с названием поля и `«Stroke»`/`«Match 1 v 1»`; при match play — карточка статуса (`matchStatus.label` крупно, «Ведёт: <имя>» или «Игроки на равных», при `closed` — «Матч решён», «Сыграно: N · Осталось: M»); список `Scoring.leaderboard(round:)`: позиция, имя, «N удар. · thru/всего», пилюля разницы (`E` при нуле, `+N`/`−N` иначе, цвета `Score.color/onColor`, для thru == 0 — «—» без заливки).

`HoleTrackerView`: (а) в тулбар — кнопка «Турнирная таблица» (`trophy`) → `router.push(.leaderboard(roundId:))`, показывать при `round.playerIds.count > 1`; (б) под шапкой лунки — горизонтальная лента игроков при `playerIds.count > 1`: аватар-инициал, имя («Вы» для себя), счётчик ударов лунки, выделение активного; тап → `model.setActiveUser(uid)`, доступен только хосту (не-хосту лента показывается, но тап по чужому — no-op с подсказкой «Счёт за других ведёт хост»); (в) заголовок серии: «Ваши удары» либо «Удары: <имя>».

- [ ] **Step 4: GREEN + build + скриншоты** (таблица; трекер с лентой игроков — на симуляторе можно проверить рендер, реальная группа — на приёмке).

- [ ] **Step 5: Commit** — `feat(ios): live leaderboard and per-player scoring in tracker`

---

### Task 6: Сквозная проверка, доки, приёмка

- [ ] **Step 1: Полный прогон** — `./ios/scripts/test.sh`, `./ios/scripts/build.sh`.
- [ ] **Step 2: Смоук на симуляторе** (соло-регресс): создать соло-раунд, записать удары, финиш — как раньше; вкладки, история, профиль, сумка не сломаны.
- [ ] **Step 3: Смоук группы (насколько возможно на одном устройстве):** создать групповой раунд → лобби показывает код и QR → «Начать раунд» → трекер (лента игроков из одного себя не показывается) → таблица открывается → финиш → итоги.
- [ ] **Step 4: Доки** — `CLAUDE.md`: 4–6 строк про групповую игру (лобби/join/leaderboard, LEAVE требует полного playerIds из-за правил, deep-link `smartgolfcaddy://join/<CODE>`, замер дистанций только для своего слота).
- [ ] **Step 5: Commit + push** — `docs: phase 3a — group play notes`.
- [ ] **Step 6 (контроллер):** сборка и установка на симулятор и iPhone; приёмка с реальным вторым игроком (второе устройство/аккаунт): вход по коду и по QR, живая таблица у обоих, хост ведёт счёт за товарища, match play статус.
