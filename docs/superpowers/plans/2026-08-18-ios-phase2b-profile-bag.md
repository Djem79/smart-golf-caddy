# iOS Phase 2b — History, Profile, Bag, Course Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Довести iOS-приложение до полного паритета с PWA для одиночной игры: штрафные удары (новая фича, обе платформы), таббар с Историей и Профилем (статистика/гандикап), Сумка клюшек (14 слотов, кастомные клюшки, юниты), Поиск гольф-полей (Places API + геолокация), иконка приложения, hardening-мелочи из беклога 2а.

**Architecture:** Те же слои. Новое: корневой TabView (Раунды/История/Профиль), каждая вкладка со своим NavigationStack; общий enum Route получает кейсы myBag/courseSearch; выбранное поле передаётся через AppStore.selectedCourse. CoursesService — порт courses.ts (Places API New, REST). GeolocationService — обёртка CLLocationManager с колбэками на main.

**Tech Stack:** SwiftUI TabView, CoreLocation, URLSession (Places API New), FirebaseFirestore (users setDoc merge).

**Spec:** `docs/superpowers/specs/2026-08-17-ios-app-design.md`. Веб-эталоны: `src/screens/{History,Profile,MyBag,CourseSearch}.tsx`, `src/services/{courses,users,scoring}.ts`, `src/hooks/useGeolocation.ts`. Решения пользователя: штраф — чип «Штраф» среди клюшек, исключается из статистики клюшек НА ОБЕИХ платформах; почтовый домен — не в этой фазе.

## Global Constraints

- Сборка/тесты ТОЛЬКО `./ios/scripts/test.sh` / `./ios/scripts/build.sh`; «стандартная тест-команда» = test.sh. FIREBASE_SOURCE_FIRESTORE не включать; Firebase-пакеты в тест-таргет не добавлять; тестам Firebase-импорт запрещён.
- `import Firebase*` — только Services/ (+ AppDelegate, DEBUG DiagnosticsView); `import GoogleSignIn` — Services/ + RootView.onOpenURL; `import CoreLocation` — только Services/GeolocationService.swift; Views/ViewModels без этих импортов.
- Колбэки сервисов — на main (инвариант проекта); каждая VM с подпиской обязана: onError→видимая ошибка+escape, отписка в `@MainActor deinit`.
- Русский UI дословно из плана; SF Symbols (никаких эмодзи); ≥48pt; фиксированные шрифты; `.preferredColorScheme(.light)` уже стоит — новые sheet/экраны не задают тёмных вариантов.
- Веб-правки (Task 1) — минимальный дифф; после них `npm run test:run` (vitest) и `npx tsc --noEmit` обязательны.
- Секреты: НОВЫЙ ключ `GOOGLE_PLACES_IOS_KEY` живёт в `ios/Config/Local.xcconfig` (gitignored) и попадает в Info.plist через переменную — НЕ в git; в `Local.xcconfig.example` — placeholder.
- Коммит после каждой задачи; сообщения — из задач.
- Интерфейсы фаз 1–2а доступны всем задачам (Route/AppRouter/AppStore/DSButton/DS*/Clubs/Scoring/Score/RoundsService/ShotQueue/SessionViewModel/AuthService/ProfileService/pluralRu/FlowLayoutCompat и т.д.).

---

### Task 1: Штрафные удары (iOS + веб, TDD)

**Files:**
- Modify: `ios/SmartGolfCaddy/Models/Club.swift` (константа + label)
- Modify: `ios/SmartGolfCaddy/Models/Scoring.swift` (исключение из clubUsage)
- Modify: `ios/SmartGolfCaddy/Views/HoleTrackerView.swift` (чип «Штраф» в пикере)
- Modify: `src/services/scoring.ts` (исключение из computeClubUsage)
- Modify: `src/types/index.ts` (константа PENALTY_ID + getClubLabel-ветка не нужна: id «Штраф» вернётся как есть — проверить тестом)
- Test: `ios/SmartGolfCaddyTests/ScoringTests.swift` (+2 теста), `src/services/scoring.test.ts` (+1 тест)

**Interfaces:**
- Produces: `Clubs.penaltyId == "Штраф"` (Swift), `PENALTY_ID = 'Штраф'` (TS, экспорт из src/types/index.ts). Штраф пишется в серию как обычный элемент clubs — сервер (Zod: массив строк) принимает без изменений; счёт (+1 удар) корректен по правилам гольфа; в статистике клюшек исключён на обеих платформах.

- [ ] **Step 1: Падающие тесты**

Swift — в `ScoringTests`:

```swift
    func testClubUsageExcludesPenalty() {
        let round = makeRound(holes: [
            hole(1, par: 4, shots: ["u1": ["count": 3, "clubs": ["Driver", "Штраф", "Putter"]]]),
        ])
        let usage = Scoring.clubUsage(round: round, userId: "u1")
        XCTAssertEqual(usage.map(\.club).sorted(), ["Driver", "Putter"])
        XCTAssertEqual(usage.first?.percent, 50)  // из 2 не-штрафных
    }

    func testPenaltyConstantAndLabel() {
        XCTAssertEqual(Clubs.penaltyId, "Штраф")
        XCTAssertEqual(Clubs.label(for: Clubs.penaltyId, in: []), "Штраф")  // id вне abbrev → как есть
    }
```

TS — в `src/services/scoring.test.ts` (найти существующий describe computeClubUsage и добавить):

```ts
  it('исключает штрафные удары из статистики клюшек', () => {
    const round = makeRound([
      hole(1, 4, { u1: { count: 3, clubs: ['Driver', 'Штраф', 'Putter'], updatedAt: new Date() } }),
    ])
    const usage = computeClubUsage(round, 'u1')
    expect(usage.map(s => s.club).sort()).toEqual(['Driver', 'Putter'])
    expect(usage[0].percent).toBe(50)
  })
```

(если хелперы makeRound/hole в тест-файле называются иначе — использовать локальные фабрики файла; поведение теста сохранить.)

- [ ] **Step 2: RED** — `./ios/scripts/test.sh` падает (нет `Clubs.penaltyId`); `npm run test:run -- src/services/scoring.test.ts` падает (штраф попадает в статистику).

- [ ] **Step 3: Реализация**

`ios/SmartGolfCaddy/Models/Club.swift` — в enum Clubs добавить:

```swift
    /// Псевдо-клюшка «Штраф»: пишется в серию как обычный удар (счёт +1 по
    /// правилам гольфа), исключается из статистики клюшек. SYNC: PENALTY_ID
    /// в src/types/index.ts.
    static let penaltyId = "Штраф"
```

`ios/SmartGolfCaddy/Models/Scoring.swift`, в `clubUsage(rounds:userId:)`:

```swift
                    if club == "Неизвестно" || club == Clubs.penaltyId { continue }
```

`ios/SmartGolfCaddy/Views/HoleTrackerView.swift`, в `clubPicker` после ForEach(pickerClubs):

```swift
                    ClubChipView(
                        label: Clubs.penaltyId,
                        selected: selectedClub == Clubs.penaltyId
                    ) {
                        selectedClub = Clubs.penaltyId
                    }
```

И в `.onChange`/`.task`-валидации selectedClub: валиден также `Clubs.penaltyId` (условие «не содержится в ids» дополнить `&& selectedClub != Clubs.penaltyId`).

`src/types/index.ts` — рядом с CLUB_ABBREV:

```ts
// Псевдо-клюшка «Штраф»: обычный элемент clubs[] (счёт +1), исключается из
// статистики клюшек. SYNC: Clubs.penaltyId в ios/SmartGolfCaddy/Models/Club.swift.
export const PENALTY_ID = 'Штраф'
```

`src/services/scoring.ts`, в computeClubUsage (импортировать PENALTY_ID):

```ts
        if (club === 'Неизвестно' || club === PENALTY_ID) continue
```

- [ ] **Step 4: GREEN** — обе стороны: `./ios/scripts/test.sh` (61+); `npm run test:run -- src/services/scoring.test.ts`; `npx tsc --noEmit`.

- [ ] **Step 5: Commit**

```bash
git add ios/SmartGolfCaddy src/services/scoring.ts src/services/scoring.test.ts src/types/index.ts ios/SmartGolfCaddyTests/ScoringTests.swift
git commit -m "feat: penalty stroke chip — counted in score, excluded from club stats (iOS+web)"
```

---

### Task 2: Таббар (Раунды/История/Профиль) + экран Истории

**Files:**
- Modify: `ios/SmartGolfCaddy/App/AppRouter.swift` (кейсы myBag/courseSearch + resetTo)
- Modify: `ios/SmartGolfCaddy/App/RootView.swift` (TabView, вынесенный RouteDestinationView)
- Create: `ios/SmartGolfCaddy/Views/HistoryView.swift`
- Create: `ios/SmartGolfCaddy/ViewModels/HistoryViewModel.swift`
- Create: `ios/SmartGolfCaddy/Views/ProfileView.swift` — ВРЕМЕННАЯ заглушка `struct ProfileView: View { var body: some View { Text("В разработке").font(DSFont.bodyMD) } }` (T3 заменит)
- Create: `ios/SmartGolfCaddy/Views/MyBagView.swift`, `ios/SmartGolfCaddy/Views/CourseSearchView.swift` — ВРЕМЕННЫЕ заглушки той же формы (`MyBagView()`, `CourseSearchView()`; T4/T5 заменят)
- Modify: `ios/SmartGolfCaddy/Views/RoundResultsView.swift` (кнопки «Новый раунд»/«На главную» → межвкладочные router.startNewRound()/router.goHome())
- Test: нет новых юнит-тестов (логика History = getUserRounds+filter, покрыта паттерном Home)

**Interfaces:**
- Produces:
  - `enum Route` дополнен: `case myBag`, `case courseSearch` (T3–T5 зовут); `AppRouter.resetTo(_ route: Route)` (path = [route])
  - `RouteDestinationView(route: Route)` — единая точка маппинга Route→экран (используется всеми вкладками)
  - Корень: `TabView` — вкладка «Раунды» (NavigationStack по router.path, корень HomeView), «История» (свой NavigationStack, корень HistoryView), «Профиль» (свой NavigationStack, корень ProfileView). Вкладки История/Профиль пушат через `NavigationLink(value: Route...)`.
  - `HistoryView` — список завершённых раундов (дата «d MMMM yyyy», лунки, игроки, счёт), пустое состояние «Нет завершённых раундов», ошибка+«Повторить», pull-to-refresh; тап → `NavigationLink(value: Route.results(roundId:))`.

- [ ] **Step 1: Роутер и корень**

`AppRouter.swift` — заменить файл целиком (enum расширен, роутер знает про вкладки — иначе кнопки «Итогов», открытых из Истории, дёргали бы стек чужой вкладки):

```swift
// ios/SmartGolfCaddy/App/AppRouter.swift
import Foundation
import Observation

enum Route: Hashable {
    case roundSetup
    case hole(roundId: String, number: Int)
    case results(roundId: String)
    case myBag
    case courseSearch
}

enum AppTab: Hashable {
    case rounds, history, profile
}

@Observable
@MainActor
final class AppRouter {
    var selectedTab: AppTab = .rounds
    var path: [Route] = []          // стек вкладки «Раунды»
    var historyPath: [Route] = []   // стек вкладки «История»
    var profilePath: [Route] = []   // стек вкладки «Профиль»

    func push(_ route: Route) {
        path.append(route)
    }

    /// Замена вершины стека «Раундов» (лунка→лунка, лунка→итоги).
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

    /// «На главную» из любого места: домой на вкладку «Раунды», все стеки чисты.
    func goHome() {
        historyPath.removeAll()
        profilePath.removeAll()
        path.removeAll()
        selectedTab = .rounds
    }

    /// «Новый раунд» из любого места: вкладка «Раунды» со стеком [настройка].
    func startNewRound() {
        historyPath.removeAll()
        profilePath.removeAll()
        path = [.roundSetup]
        selectedTab = .rounds
    }
}
```

В `RoundResultsView.swift` кнопки перевести: «Новый раунд» → `router.startNewRound()`, «На главную» и toolbar-«домик» → `router.goHome()` (это чинит и вызовы из вкладки История).

`RootView.swift` — заменить `.signedIn`-ветку и destination:

```swift
            case .signedIn:
                TabView(selection: $router.selectedTab) {
                    NavigationStack(path: $router.path) {
                        HomeView()
                            .navigationDestination(for: Route.self) { route in
                                // .id(route): смена значения Route обязана пересоздать
                                // экран (урок 2а: иначе старый @State пишет в чужую лунку).
                                RouteDestinationView(route: route).id(route)
                            }
                            .toolbar(.hidden, for: .navigationBar)
                    }
                    .tabItem { Label("Раунды", systemImage: "figure.golf") }
                    .tag(AppTab.rounds)

                    NavigationStack(path: $router.historyPath) {
                        HistoryView()
                            .navigationDestination(for: Route.self) { route in
                                RouteDestinationView(route: route).id(route)
                            }
                    }
                    .tabItem { Label("История", systemImage: "clock.arrow.circlepath") }
                    .tag(AppTab.history)

                    NavigationStack(path: $router.profilePath) {
                        ProfileView()
                            .navigationDestination(for: Route.self) { route in
                                RouteDestinationView(route: route).id(route)
                            }
                    }
                    .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
                    .tag(AppTab.profile)
                }
                .tint(DSColor.primary)
```

И вынести маппинг в файл RootView.swift (ниже структуры):

```swift
struct RouteDestinationView: View {
    let route: Route

    var body: some View {
        switch route {
        case .roundSetup:
            RoundSetupView()
        case .hole(let roundId, let number):
            HoleTrackerView(roundId: roundId, holeNumber: number)
        case .results(let roundId):
            RoundResultsView(roundId: roundId)
        case .myBag:
            MyBagView()
        case .courseSearch:
            CourseSearchView()
        }
    }
}
```

Для сборки Task 2: создать ВРЕМЕННЫЕ заглушки `MyBagView.swift` и `CourseSearchView.swift` (по образцу заглушек 2а: `Text("В разработке")`) — T4/T5 заменят. ProfileView — заглушка из Files-списка.

Примечание: комментарий про `.id(route)` из 2а сохранить над первым RouteDestinationView-вызовом (критичный урок).

- [ ] **Step 2: HistoryViewModel + HistoryView**

```swift
// ios/SmartGolfCaddy/ViewModels/HistoryViewModel.swift
import Foundation
import Observation

@Observable
@MainActor
final class HistoryViewModel {
    var rounds: [Round] = []
    var loading = true
    var loadError = false

    func load(userId: String) async {
        loading = true
        loadError = false
        defer { loading = false }
        do {
            let all = try await RoundsService.getUserRounds(userId: userId)
            rounds = all.filter { $0.status == .finished }
        } catch {
            loadError = true
        }
    }
}
```

```swift
// ios/SmartGolfCaddy/Views/HistoryView.swift
import SwiftUI

struct HistoryView: View {
    @State private var model = HistoryViewModel()

    private var currentUserId: String? { AuthService.currentUserId }

    var body: some View {
        Group {
            if model.loadError {
                errorState
            } else if model.loading {
                ProgressView("Загрузка...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.rounds.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(DSColor.surface)
        .navigationTitle("История раундов")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let uid = currentUserId { await model.load(userId: uid) }
        }
        .refreshable {
            if let uid = currentUserId { await model.load(userId: uid) }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(model.rounds) { round in
                    NavigationLink(value: Route.results(roundId: round.id)) {
                        row(round)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DS.screenPadding)
        }
    }

    private func row(_ round: Round) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(round.courseName)
                    .font(DSFont.bodyMD)
                    .foregroundStyle(DSColor.onSurface)
                    .lineLimit(1)
                Text(subtitle(round))
                    .font(DSFont.labelLG)
                    .foregroundStyle(DSColor.onSurfaceVariant)
            }
            Spacer()
            if let uid = currentUserId {
                let totals = Scoring.playerTotals(round: round, userId: uid)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(totals.totalScore)")
                        .font(DSFont.titleLG)
                        .foregroundStyle(DSColor.primary)
                        .monospacedDigit()
                    Text("\(totals.scoreDiff >= 0 ? "+" : "")\(totals.scoreDiff)")
                        .font(DSFont.labelMD)
                        .foregroundStyle(DSColor.onSurfaceVariant)
                        .monospacedDigit()
                }
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

    private func subtitle(_ round: Round) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        let date = formatter.string(from: round.createdAt)
        let players = round.players.count
        return "\(date) · \(round.totalHoles) \(pluralRu(round.totalHoles, "лунка", "лунки", "лунок")) · \(players) \(pluralRu(players, "игрок", "игрока", "игроков"))"
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "flag")
                .font(.system(size: 26))
                .foregroundStyle(DSColor.onSurfaceVariant)
                .frame(width: 56, height: 56)
                .background(DSColor.surfaceContainer)
                .clipShape(Circle())
            Text("Нет завершённых раундов")
                .font(DSFont.bodyMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorState: some View {
        VStack(spacing: 16) {
            Text("Не удалось загрузить историю")
                .font(DSFont.bodyMD)
                .foregroundStyle(DSColor.onSurface)
            DSButton(title: "Повторить", style: .secondary) {
                Task {
                    if let uid = currentUserId { await model.load(userId: uid) }
                }
            }
            .padding(.horizontal, 64)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 3: Сборка+тесты+рендер-скриншот** — `./ios/scripts/test.sh` зелёный; `./ios/scripts/build.sh`; установка на симулятор; скриншот: внизу таббар с тремя вкладками; вкладка «История» — либо список, либо пустое состояние (пользователь залогинен с приёмки 2а — должен быть список раундов).

- [ ] **Step 4: Commit**

```bash
git add ios/SmartGolfCaddy
git commit -m "feat(ios): tab bar (rounds/history/profile) + history screen"
```

---

### Task 3: Экран Профиля (статистика, гандикап, распределение)

**Files:**
- Modify: `ios/SmartGolfCaddy/Views/ProfileView.swift` (замена заглушки)
- Create: `ios/SmartGolfCaddy/ViewModels/ProfileViewModel.swift`

**Interfaces:**
- Consumes: `RoundsService.getUserRounds`, `Scoring.playerStats/.handicap/.clubUsage(rounds:)`, `Score.color`, `SessionViewModel` (.profile/.signOut), `Clubs.label(for:in:)`, `pluralRu`, `Route.myBag`.
- Produces: `ProfileView()` — карточка юзера (имя/иконка), «Статистика» (Раундов/Ср. удары/Лучший счёт/Best vs Par), «Распределение по лункам» (stacked bar + легенда 6 категорий), «Гандикап» (index или подсказка «минимум 3 раунда»), «Любимые клюшки» (top-5 с прогресс-барами), карточка «Моя сумка» → NavigationLink(Route.myBag), кнопка «Выйти из аккаунта».

- [ ] **Step 1: Реализация**

```swift
// ios/SmartGolfCaddy/ViewModels/ProfileViewModel.swift
import Foundation
import Observation

@Observable
@MainActor
final class ProfileViewModel {
    var rounds: [Round] = []
    var loadError = false

    func load(userId: String) async {
        loadError = false
        do {
            rounds = try await RoundsService.getUserRounds(userId: userId)
        } catch {
            loadError = true
        }
    }
}
```

```swift
// ios/SmartGolfCaddy/Views/ProfileView.swift — заменить заглушку целиком
import SwiftUI

struct ProfileView: View {
    @Environment(SessionViewModel.self) private var session
    @State private var model = ProfileViewModel()

    private var currentUserId: String? { AuthService.currentUserId }
    private var bag: [BagClub] { session.profile?.resolvedBag ?? Clubs.defaultBag }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if model.loadError { errorBanner }
                userCard
                statsCard
                if let stats = statsIfPlayed, stats.totalHolesPlayed > 0 {
                    distributionCard(stats)
                }
                handicapCard
                favoriteClubsCard
                bagLink
                DSButton(title: "Выйти из аккаунта", style: .secondary) {
                    session.signOut()
                }
            }
            .padding(DS.screenPadding)
        }
        .background(DSColor.surface)
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let uid = currentUserId { await model.load(userId: uid) }
        }
        .refreshable {
            if let uid = currentUserId { await model.load(userId: uid) }
        }
    }

    private var statsIfPlayed: PlayerStats? {
        guard let uid = currentUserId else { return nil }
        return Scoring.playerStats(rounds: model.rounds, userId: uid)
    }

    private var errorBanner: some View {
        HStack(spacing: 12) {
            Text("Не удалось загрузить статистику")
                .font(DSFont.labelLG)
                .foregroundStyle(DSColor.onSurface)
            Spacer()
            Button("Повторить") {
                Task {
                    if let uid = currentUserId { await model.load(userId: uid) }
                }
            }
            .font(DSFont.labelLG)
            .foregroundStyle(DSColor.primary)
            .frame(minHeight: DS.touchTarget)
        }
        .padding(.horizontal, 14)
        .background(DSColor.errorContainer.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
    }

    private var userCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(DSColor.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.profile?.name ?? "Голфер")
                    .font(DSFont.titleLG)
                    .foregroundStyle(DSColor.onSurface)
                    .lineLimit(1)
                Text("Гандикап профиля: \(Int(session.profile?.handicap ?? 0))")
                    .font(DSFont.labelLG)
                    .foregroundStyle(DSColor.onSurfaceVariant)
            }
            Spacer()
        }
        .padding(16)
        .background(DSColor.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: DS.cornerRadius).stroke(DSColor.outlineVariant.opacity(0.25)))
    }

    private var statsCard: some View {
        card(title: "Статистика") {
            if let stats = statsIfPlayed, stats.roundsPlayed > 0 {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    statCell("РАУНДОВ", "\(stats.roundsPlayed)")
                    statCell("СР. УДАРЫ", stats.avgShots.truncatingRemainder(dividingBy: 1) == 0
                             ? String(format: "%.0f", stats.avgShots)
                             : String(format: "%.1f", stats.avgShots))
                    statCell("ЛУЧШИЙ СЧЁТ", stats.bestScore.map(String.init) ?? "—")
                    statCell("BEST VS PAR", stats.bestScoreDiff.map { $0 > 0 ? "+\($0)" : "\($0)" } ?? "—")
                }
            } else {
                Text("Сыграйте первый раунд, чтобы увидеть статистику.")
                    .font(DSFont.labelLG)
                    .foregroundStyle(DSColor.onSurfaceVariant)
            }
        }
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(DSFont.labelMD)
                .tracking(1.2)
                .foregroundStyle(DSColor.onSurfaceVariant)
            Text(value)
                .font(DSFont.headlineMD)
                .foregroundStyle(DSColor.primary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func distributionCard(_ stats: PlayerStats) -> some View {
        let items: [(label: String, count: Int, hex: String)] = [
            ("Eagle+", stats.holeStats.eagle, Score.color(-2)),
            ("Birdie", stats.holeStats.birdie, Score.color(-1)),
            ("Par", stats.holeStats.par, Score.color(0)),
            ("Bogey", stats.holeStats.bogey, Score.color(1)),
            ("Double", stats.holeStats.double, Score.color(2)),
            ("Хуже", stats.holeStats.worse, Score.color(3)),
        ]
        let total = stats.totalHolesPlayed
        func pct(_ n: Int) -> Int { total > 0 ? Int((Double(n) / Double(total) * 100).rounded()) : 0 }
        return card(title: "Распределение по лункам") {
            Text("За все \(total) \(pluralRu(total, "сыгранную лунку", "сыгранных лунки", "сыгранных лунок"))")
                .font(DSFont.labelMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(items.filter { $0.count > 0 }, id: \.label) { item in
                        Rectangle()
                            .fill(Color(hex: item.hex))
                            .frame(width: geo.size.width * CGFloat(item.count) / CGFloat(max(total, 1)))
                    }
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())
            .background(Capsule().fill(DSColor.surfaceContainer))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(items, id: \.label) { item in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: item.hex))
                            .frame(width: 12, height: 12)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(DSColor.outlineVariant.opacity(0.3)))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.label)
                                .font(DSFont.labelMD)
                                .foregroundStyle(DSColor.onSurface)
                                .lineLimit(1)
                            Text("\(item.count) · \(pct(item.count))%")
                                .font(DSFont.labelMD)
                                .foregroundStyle(DSColor.onSurfaceVariant)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var handicapCard: some View {
        card(title: "Гандикап") {
            if let uid = currentUserId,
               let handicap = Scoring.handicap(rounds: model.rounds, userId: uid) {
                Text(handicap.index >= 0
                     ? String(format: "%.1f", handicap.index)
                     : String(format: "+%.1f", abs(handicap.index)))
                    .font(DSFont.displayLG)
                    .foregroundStyle(DSColor.primary)
                    .monospacedDigit()
                Text(handicap.bestUsed == 8
                     ? "по лучшим 8 из \(handicap.basedOnRounds) раундов · WHS-метод (без course rating / slope)"
                     : "по \(handicap.basedOnRounds) \(pluralRu(handicap.basedOnRounds, "раунду", "раундам", "раундам")), среднее × 0.96")
                    .font(DSFont.labelMD)
                    .foregroundStyle(DSColor.onSurfaceVariant)
            } else {
                Text("Сыграйте минимум 3 раунда — рассчитаем по WHS (best 8 из последних 20 × 0.96).")
                    .font(DSFont.labelLG)
                    .foregroundStyle(DSColor.onSurfaceVariant)
            }
        }
    }

    private var favoriteClubsCard: some View {
        card(title: "Любимые клюшки") {
            if let uid = currentUserId {
                let stats = Array(Scoring.clubUsage(rounds: model.rounds, userId: uid).prefix(5))
                if stats.isEmpty {
                    Text("Статистика появится после первых ударов.")
                        .font(DSFont.labelLG)
                        .foregroundStyle(DSColor.onSurfaceVariant)
                } else {
                    let maxCount = stats.first?.count ?? 1
                    VStack(spacing: 10) {
                        ForEach(stats) { stat in
                            VStack(spacing: 4) {
                                HStack {
                                    Text(Clubs.label(for: stat.club, in: bag))
                                        .font(DSFont.bodyMD)
                                        .foregroundStyle(DSColor.onSurface)
                                    Spacer()
                                    Text("\(stat.count) \(pluralRu(stat.count, "удар", "удара", "ударов")) · \(stat.percent)%")
                                        .font(DSFont.labelMD)
                                        .foregroundStyle(DSColor.onSurfaceVariant)
                                }
                                GeometryReader { geo in
                                    Capsule()
                                        .fill(DSColor.primary)
                                        .frame(width: geo.size.width * CGFloat(stat.count) / CGFloat(max(maxCount, 1)))
                                }
                                .frame(height: 8)
                                .background(Capsule().fill(DSColor.surfaceContainer))
                            }
                        }
                    }
                }
            }
        }
    }

    private var bagLink: some View {
        NavigationLink(value: Route.myBag) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "briefcase")
                        .font(.system(size: 20))
                        .foregroundStyle(DSColor.onPrimary)
                        .frame(width: 44, height: 44)
                        .background(DSColor.onPrimary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text("МОЯ СУМКА")
                        .font(DSFont.labelLG)
                        .tracking(2.5)
                        .foregroundStyle(DSColor.onPrimary)
                }
                HStack {
                    Text("\(bag.filter(\.enabled).count) клюшек · \(session.profile?.units == .yd ? "ярды" : "метры")")
                        .font(DSFont.bodyMD)
                        .foregroundStyle(DSColor.onPrimary.opacity(0.85))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(DSColor.onPrimary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [DSColor.primaryContainer, DSColor.primary],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
        }
        .buttonStyle(.plain)
    }

    private func card(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(DSFont.titleLG)
                .foregroundStyle(DSColor.onSurface)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: DS.cornerRadius).stroke(DSColor.outlineVariant.opacity(0.25)))
    }
}
```

Замечания:
- Аватар — SF Symbol (сетевой аватар Google — отдельная фича, не в 2б; email юзера в карточке не показываем — в AppUser его нет, это осознанное упрощение против веба).
- «Гандикап профиля» в userCard — поле handicap из Firestore-профиля (веб его не показывает в карточке; показываем как полезную деталь).

- [ ] **Step 2: Сборка+тесты+скриншот** — test.sh зелёный; build.sh; вкладка «Профиль»: у пользователя есть завершённые раунды → статистика с числами, распределение, «Любимые клюшки»; тап «МОЯ СУМКА» → заглушка.

- [ ] **Step 3: Commit**

```bash
git add ios/SmartGolfCaddy/Views/ProfileView.swift ios/SmartGolfCaddy/ViewModels/ProfileViewModel.swift
git commit -m "feat(ios): profile screen — stats, hole distribution, handicap, favorite clubs"
```

---

### Task 4: Сумка клюшек (TDD для логики)

**Files:**
- Create: `ios/SmartGolfCaddy/Services/UsersService.swift`
- Create: `ios/SmartGolfCaddy/ViewModels/MyBagViewModel.swift`
- Modify: `ios/SmartGolfCaddy/Views/MyBagView.swift` (замена заглушки)
- Modify: `ios/SmartGolfCaddy/Models/Club.swift` (BagClub.firestoreData уже есть из 2а-T2? НЕТ — firestoreData есть; проверить; groups label доступ)
- Test: `ios/SmartGolfCaddyTests/MyBagViewModelTests.swift`

**Interfaces:**
- Consumes: `SessionViewModel.profile` (риалтайм-снапшот сумки), `Clubs.groups/.defaultBag/.category(of:)`, `BagClub.firestoreData`, `Score.metersToYards/.yardsToMeters`, `DistanceUnit`.
- Produces:
  - `UsersService.updateBag(uid:bag:) async throws` (setDoc merge `{bag: [...]}`), `UsersService.updateUnits(uid:units:) async throws`
  - `MyBagViewModel`: `bag: [BagClub]`, `units: DistanceUnit`, `saving`, `errorMessage`; `syncFromProfile(_ profile: AppUser?)`; `toggle(id:)`, `setName(id:name:)`, `setDistance(id:raw:)`, `addCustomClub(category:name:distance:)`, `deleteClub(id:)`, `moveClub(inCategory:from:to:)`, `changeUnits(_:)` — все async, оптимистично мутируют bag и персистят; `clubsInGroup(_:)`, `distanceValue(for:)`, `enabledCount`
  - `MyBagView()`: счётчик N/14 с прогресс-баром, тумблер Метры/Ярды, группы (Clubs.groups) в List-секциях: строка = чекбокс-вкл, лейбл, поле «Модель»/«Название», поле дистанции (submit/blur), у кастомных — swipe-delete; reorder внутри секции через drag (List+onMove, EditButton не нужен — включаем `.moveDisabled(false)` и long-press drag в List с `.environment(\.editMode, .constant(.active))`? — НЕТ: используем обычный List с onMove и стандартным drag-handle в edit-режиме, включаемым кнопкой «Порядок» в тулбаре); кнопка «+ Добавить клюшку» в каждой группе → sheet (имя, дистанция).

**Логика паритета:** persist пишет ВЕСЬ массив bag (веб updateBag); дистанции хранятся в метрах, показываются в выбранных юнитах (конверсия при вводе); USGA-лимит 14 — не hard-блок (как в вебе: счётчик показывает N/14, «Свободных слотов»), добавление кастомной — insert в конец категории.

- [ ] **Step 1: Падающие тесты**

```swift
// ios/SmartGolfCaddyTests/MyBagViewModelTests.swift
import XCTest
@testable import SmartGolfCaddy

final class MyBagViewModelTests: XCTestCase {

    @MainActor
    private func makeModel() -> MyBagViewModel {
        let model = MyBagViewModel(persistBag: { _ in }, persistUnits: { _ in })
        model.syncFromProfile(nil)  // nil → defaultBag, метры
        return model
    }

    @MainActor
    func testSyncFromNilProfileGivesDefaultBag() {
        let model = makeModel()
        XCTAssertEqual(model.bag, Clubs.defaultBag)
        XCTAssertEqual(model.units, .m)
        XCTAssertEqual(model.enabledCount, 10)
    }

    @MainActor
    func testToggleFlipsEnabled() async {
        let model = makeModel()
        await model.toggle(id: "5W")
        XCTAssertTrue(model.bag.first { $0.id == "5W" }!.enabled)
        await model.toggle(id: "5W")
        XCTAssertFalse(model.bag.first { $0.id == "5W" }!.enabled)
    }

    @MainActor
    func testSetDistanceConvertsYards() async {
        let model = makeModel()
        model.units = .yd
        await model.setDistance(id: "7i", raw: "150")  // 150 ярдов → 137 м
        XCTAssertEqual(model.bag.first { $0.id == "7i" }!.distanceMeters, Score.yardsToMeters(150))
    }

    @MainActor
    func testSetDistanceIgnoresInvalid() async {
        let model = makeModel()
        let before = model.bag.first { $0.id == "7i" }!.distanceMeters
        await model.setDistance(id: "7i", raw: "abc")
        await model.setDistance(id: "7i", raw: "-5")
        XCTAssertEqual(model.bag.first { $0.id == "7i" }!.distanceMeters, before)
    }

    @MainActor
    func testAddCustomClubInsertsAtCategoryEnd() async {
        let model = makeModel()
        await model.addCustomClub(category: .wood, name: "Stealth 2", distance: 220)
        let woods = model.clubsInGroup(.wood)
        XCTAssertEqual(woods.last?.customName, "Stealth 2")
        XCTAssertTrue(woods.last!.id.hasPrefix("custom-"))
        XCTAssertTrue(woods.last!.enabled)
        // Кастомная НЕ в конце всего массива — паттерн веба (не позади паттера)
        XCTAssertNotEqual(model.bag.last?.customName, "Stealth 2")
    }

    @MainActor
    func testDeleteClub() async {
        let model = makeModel()
        await model.addCustomClub(category: .iron, name: "X", distance: 100)
        let id = model.clubsInGroup(.iron).last!.id
        await model.deleteClub(id: id)
        XCTAssertNil(model.bag.first { $0.id == id })
    }

    @MainActor
    func testMoveWithinCategory() async {
        let model = makeModel()
        // woods: Driver, 3W, 5W, Hybrid → переставить Driver в конец группы
        await model.moveClub(inCategory: .wood, from: IndexSet(integer: 0), to: 4)
        XCTAssertEqual(model.clubsInGroup(.wood).map(\.id), ["3W", "5W", "Hybrid", "Driver"])
        // айроны не задеты
        XCTAssertEqual(model.clubsInGroup(.iron).first?.id, "3i")
    }

    @MainActor
    func testPersistFailureShowsErrorAndKeepsOptimism() async {
        struct Boom: Error {}
        let model = MyBagViewModel(persistBag: { _ in throw Boom() }, persistUnits: { _ in })
        model.syncFromProfile(nil)
        await model.toggle(id: "5W")
        XCTAssertEqual(model.errorMessage, "Не удалось сохранить изменения")
        XCTAssertTrue(model.bag.first { $0.id == "5W" }!.enabled)  // оптимизм не откатываем (веб-паритет)
    }
}
```

- [ ] **Step 2: RED.**

- [ ] **Step 3: Реализация**

```swift
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
```

```swift
// ios/SmartGolfCaddy/ViewModels/MyBagViewModel.swift
// Порт логики MyBag.tsx. Оптимистичные мутации: локально применяем сразу,
// затем персистим ВЕСЬ массив (веб-паритет updateBag); при ошибке показываем
// сообщение, оптимизм не откатываем (следующий снапшот профиля выправит).
import Foundation
import Observation

@Observable
@MainActor
final class MyBagViewModel {
    static let totalSlots = 14

    var bag: [BagClub] = Clubs.defaultBag
    var units: DistanceUnit = .m
    var saving = false
    var errorMessage: String?

    private let persistBag: ([BagClub]) async throws -> Void
    private let persistUnits: (DistanceUnit) async throws -> Void
    private var synced = false

    /// Прод-инициализатор: персист в Firestore текущего пользователя.
    convenience init() {
        self.init(
            persistBag: { bag in
                guard let uid = AuthService.currentUserId else { return }
                try await UsersService.updateBag(uid: uid, bag: bag)
            },
            persistUnits: { units in
                guard let uid = AuthService.currentUserId else { return }
                try await UsersService.updateUnits(uid: uid, units: units)
            }
        )
    }

    init(persistBag: @escaping ([BagClub]) async throws -> Void,
         persistUnits: @escaping (DistanceUnit) async throws -> Void) {
        self.persistBag = persistBag
        self.persistUnits = persistUnits
    }

    /// Синхронизация из снапшота профиля. Первый снапшот заполняет стейт;
    /// последующие применяем только когда нет незасейвленного оптимизма
    /// (saving == false), чтобы не затирать ввод пользователя.
    func syncFromProfile(_ profile: AppUser?) {
        guard !saving || !synced else { return }
        bag = Clubs.resolveBag(bag: profile?.bag, legacyClubs: profile?.legacyClubs)
        units = profile?.units ?? .m
        synced = true
    }

    var enabledCount: Int { bag.filter(\.enabled).count }

    func clubsInGroup(_ category: ClubCategory) -> [BagClub] {
        bag.filter { Clubs.category(of: $0) == category }
    }

    func distanceValue(for club: BagClub) -> Int {
        if Clubs.category(of: club) == .putter { return 0 }
        return units == .yd ? Score.metersToYards(club.distanceMeters) : club.distanceMeters
    }

    private func persist(_ next: [BagClub]) async {
        bag = next
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            try await persistBag(next)
        } catch {
            errorMessage = "Не удалось сохранить изменения"
        }
    }

    func toggle(id: String) async {
        await persist(bag.map { club in
            guard club.id == id else { return club }
            var patched = club
            patched.enabled.toggle()
            return patched
        })
    }

    func setName(id: String, name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let club = bag.first(where: { $0.id == id }),
              (club.customName ?? "") != trimmed else { return }
        await persist(bag.map { club in
            guard club.id == id else { return club }
            var patched = club
            patched.customName = trimmed.isEmpty ? nil : trimmed
            return patched
        })
    }

    func setDistance(id: String, raw: String) async {
        guard let num = Int(raw), num >= 0 else { return }
        let meters = units == .yd ? Score.yardsToMeters(num) : num
        guard let club = bag.first(where: { $0.id == id }),
              club.distanceMeters != meters else { return }
        await persist(bag.map { club in
            guard club.id == id else { return club }
            var patched = club
            patched.distanceMeters = meters
            return patched
        })
    }

    func changeUnits(_ newUnits: DistanceUnit) async {
        guard newUnits != units else { return }
        units = newUnits
        do {
            try await persistUnits(newUnits)
        } catch {
            // non-critical (веб-паритет)
        }
    }

    func addCustomClub(category: ClubCategory, name: String, distance: Int) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let meters = units == .yd ? Score.yardsToMeters(distance) : distance
        let newClub = BagClub(
            id: "custom-\(UUID().uuidString.prefix(8))",
            customName: trimmed,
            distanceMeters: meters,
            enabled: true,
            category: category,
            custom: true
        )
        // Вставка в конец категории (не в конец массива) — паттерн веба:
        // пикер клюшек в трекере идёт по порядку массива.
        var insertAt = bag.count
        for index in stride(from: bag.count - 1, through: 0, by: -1)
        where Clubs.category(of: bag[index]) == category {
            insertAt = index + 1
            break
        }
        var next = bag
        next.insert(newClub, at: insertAt)
        await persist(next)
    }

    func deleteClub(id: String) async {
        await persist(bag.filter { $0.id != id })
    }

    /// Перестановка внутри категории (List.onMove даёт индексы среза группы).
    func moveClub(inCategory category: ClubCategory, from source: IndexSet, to destination: Int) async {
        var group = clubsInGroup(category)
        group.move(fromOffsets: source, toOffset: destination)
        // Собираем bag заново: клюшки категории — в новом порядке, остальные на местах.
        var iterator = group.makeIterator()
        let next = bag.map { club in
            Clubs.category(of: club) == category ? iterator.next()! : club
        }
        await persist(next)
    }
}
```

```swift
// ios/SmartGolfCaddy/Views/MyBagView.swift — заменить заглушку целиком
import SwiftUI

struct MyBagView: View {
    @Environment(SessionViewModel.self) private var session
    @State private var model = MyBagViewModel()
    @State private var addingCategory: ClubCategory?
    @State private var reordering = false

    var body: some View {
        List {
            Section {
                counterCard
                    .listRowInsets(EdgeInsets(top: 8, leading: DS.screenPadding, bottom: 4, trailing: DS.screenPadding))
                    .listRowSeparator(.hidden)
                unitsToggle
                    .listRowInsets(EdgeInsets(top: 4, leading: DS.screenPadding, bottom: 4, trailing: DS.screenPadding))
                    .listRowSeparator(.hidden)
                if let message = model.errorMessage {
                    Text(message)
                        .font(DSFont.labelLG)
                        .foregroundStyle(DSColor.error)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                }
            }
            .listRowBackground(DSColor.surface)

            ForEach(Clubs.groups, id: \.category) { group in
                Section {
                    ForEach(model.clubsInGroup(group.category)) { club in
                        ClubRowView(
                            club: club,
                            units: model.units,
                            distanceValue: model.distanceValue(for: club),
                            isPutter: Clubs.category(of: club) == .putter,
                            onToggle: { Task { await model.toggle(id: club.id) } },
                            onSetName: { name in Task { await model.setName(id: club.id, name: name) } },
                            onSetDistance: { raw in Task { await model.setDistance(id: club.id, raw: raw) } }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if club.custom == true {
                                Button(role: .destructive) {
                                    Task { await model.deleteClub(id: club.id) }
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .onMove { source, destination in
                        Task { await model.moveClub(inCategory: group.category, from: source, to: destination) }
                    }
                    Button {
                        addingCategory = group.category
                    } label: {
                        Label("Добавить клюшку", systemImage: "plus")
                            .font(DSFont.labelLG)
                            .foregroundStyle(DSColor.primary)
                            .frame(maxWidth: .infinity, minHeight: DS.touchTarget)
                    }
                } header: {
                    HStack {
                        Text(group.label)
                            .font(DSFont.titleLG)
                            .foregroundStyle(DSColor.onSurface)
                        Spacer()
                        Text("\(model.clubsInGroup(group.category).filter(\.enabled).count)/\(model.clubsInGroup(group.category).count)")
                            .font(DSFont.labelMD)
                            .foregroundStyle(DSColor.onSurfaceVariant)
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DSColor.surface)
        .environment(\.editMode, .constant(reordering ? .active : .inactive))
        .navigationTitle("Моя сумка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if model.saving {
                    Text("Сохранение...")
                        .font(DSFont.labelMD)
                        .foregroundStyle(DSColor.onSurfaceVariant)
                } else {
                    Button(reordering ? "Готово" : "Порядок") {
                        reordering.toggle()
                    }
                    .font(DSFont.labelLG)
                }
            }
        }
        .task { model.syncFromProfile(session.profile) }
        .onChange(of: session.profile) { _, profile in
            model.syncFromProfile(profile)
        }
        .sheet(item: $addingCategory) { category in
            AddClubSheet(category: category, units: model.units) { name, distance in
                Task {
                    await model.addCustomClub(category: category, name: name, distance: distance)
                    addingCategory = nil
                }
            } onCancel: {
                addingCategory = nil
            }
        }
    }

    private var counterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Состав сумки")
                        .font(DSFont.headlineMD)
                        .foregroundStyle(DSColor.primary)
                    Text("До 14 клюшек по правилам")
                        .font(DSFont.labelMD)
                        .foregroundStyle(DSColor.onSurfaceVariant)
                }
                Spacer()
                Text("\(model.enabledCount)")
                    .font(DSFont.displayLG)
                    .foregroundStyle(DSColor.primary)
                    .monospacedDigit()
                + Text("/\(MyBagViewModel.totalSlots)")
                    .font(DSFont.titleLG)
                    .foregroundStyle(DSColor.onSurfaceVariant)
            }
            GeometryReader { geo in
                Capsule()
                    .fill(DSColor.primary)
                    .frame(width: geo.size.width * CGFloat(min(model.enabledCount, MyBagViewModel.totalSlots)) / CGFloat(MyBagViewModel.totalSlots))
            }
            .frame(height: 8)
            .background(Capsule().fill(DSColor.surfaceContainerHigh))
            if model.enabledCount < MyBagViewModel.totalSlots {
                Text("Свободных слотов: \(MyBagViewModel.totalSlots - model.enabledCount)")
                    .font(DSFont.labelMD)
                    .foregroundStyle(DSColor.onSurfaceVariant)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(DSColor.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: DS.cornerRadius).stroke(DSColor.outlineVariant.opacity(0.25)))
    }

    private var unitsToggle: some View {
        HStack(spacing: 0) {
            ForEach([DistanceUnit.m, DistanceUnit.yd], id: \.self) { unit in
                Button {
                    Task { await model.changeUnits(unit) }
                } label: {
                    Text(unit == .m ? "Метры" : "Ярды")
                        .font(DSFont.labelLG)
                        .frame(maxWidth: .infinity, minHeight: DS.touchTarget)
                }
                .background(model.units == unit ? DSColor.surfaceContainerLowest : .clear)
                .foregroundStyle(model.units == unit ? DSColor.primary : DSColor.onSurfaceVariant)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(4)
        .background(DSColor.surfaceContainer)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

extension ClubCategory: Identifiable {
    public var id: String { rawValue }
}

private struct ClubRowView: View {
    let club: BagClub
    let units: DistanceUnit
    let distanceValue: Int
    let isPutter: Bool
    let onToggle: () -> Void
    let onSetName: (String) -> Void
    let onSetDistance: (String) -> Void

    @State private var nameText: String = ""
    @State private var distanceText: String = ""
    @FocusState private var nameFocused: Bool
    @FocusState private var distanceFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(club.customName ?? Clubs.abbrev[club.id] ?? club.id)
                .font(DSFont.labelLG)
                .foregroundStyle(club.enabled ? DSColor.onSurface : DSColor.onSurfaceVariant)
                .frame(width: 56, alignment: .leading)
                .lineLimit(1)
            TextField(club.custom == true ? "Название" : "Модель", text: $nameText)
                .font(DSFont.labelMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
                .focused($nameFocused)
                .onChange(of: nameFocused) { _, focused in
                    if !focused { onSetName(nameText) }
                }
            if isPutter {
                Text("—")
                    .font(DSFont.labelMD)
                    .foregroundStyle(DSColor.onSurfaceVariant)
                    .frame(width: 56)
            } else {
                HStack(spacing: 2) {
                    TextField("", text: $distanceText)
                        .keyboardType(.numberPad)
                        .font(DSFont.labelLG)
                        .foregroundStyle(DSColor.onSurface)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 44)
                        .focused($distanceFocused)
                        .onChange(of: distanceFocused) { _, focused in
                            if !focused { onSetDistance(distanceText) }
                        }
                    Text(units == .yd ? "я" : "м")
                        .font(DSFont.labelMD)
                        .foregroundStyle(DSColor.onSurfaceVariant)
                }
                .padding(.horizontal, 6)
                .frame(minHeight: 36)
                .background(DSColor.surfaceContainer)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Button(action: onToggle) {
                Image(systemName: club.enabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(club.enabled ? DSColor.primary : DSColor.outlineVariant)
                    .frame(minWidth: DS.touchTarget, minHeight: DS.touchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Включить \(club.customName ?? club.id) в сумку")
        }
        .onAppear {
            nameText = club.customName ?? ""
            distanceText = String(distanceValue)
        }
        .onChange(of: distanceValue) { _, value in
            if !distanceFocused { distanceText = String(value) }
        }
    }
}

private struct AddClubSheet: View {
    let category: ClubCategory
    let units: DistanceUnit
    let onAdd: (String, Int) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var distanceText = ""

    private var categoryLabel: String {
        Clubs.groups.first { $0.category == category }?.label ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Новая клюшка · \(categoryLabel)")
                .font(DSFont.titleLG)
                .foregroundStyle(DSColor.onSurface)
            TextField("Название (например: Stealth 2 HD)", text: $name)
                .font(DSFont.bodyMD)
                .padding(14)
                .background(DSColor.surfaceContainerLow)
                .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
            TextField(units == .yd ? "Дистанция, ярды" : "Дистанция, метры", text: $distanceText)
                .keyboardType(.numberPad)
                .font(DSFont.bodyMD)
                .padding(14)
                .background(DSColor.surfaceContainerLow)
                .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
            HStack(spacing: 8) {
                DSButton(title: "Отмена", style: .secondary, action: onCancel)
                DSButton(title: "Добавить",
                         disabled: name.trimmingCharacters(in: .whitespaces).isEmpty || Int(distanceText) == nil) {
                    if let distance = Int(distanceText) {
                        onAdd(name, distance)
                    }
                }
            }
        }
        .padding(20)
        .presentationDetents([.medium])
    }
}
```

- [ ] **Step 4: GREEN + сборка + скриншот** (сумка с группами, счётчик N/14; тумблер юнитов).

- [ ] **Step 5: Commit**

```bash
git add ios/SmartGolfCaddy ios/SmartGolfCaddyTests/MyBagViewModelTests.swift
git commit -m "feat(ios): my bag — 14 slots, units, custom clubs, reorder, distances"
```

---

### Task 5: Поиск гольф-полей (Places API + геолокация)

**Files:**
- Create: `ios/SmartGolfCaddy/Services/CoursesService.swift`
- Create: `ios/SmartGolfCaddy/Services/GeolocationService.swift`
- Create: `ios/SmartGolfCaddy/Models/Course.swift` (CourseResult)
- Create: `ios/SmartGolfCaddy/ViewModels/CourseSearchViewModel.swift`
- Modify: `ios/SmartGolfCaddy/Views/CourseSearchView.swift` (замена заглушки)
- Modify: `ios/SmartGolfCaddy/ViewModels/AppStore.swift` (+selectedCourse)
- Modify: `ios/SmartGolfCaddy/Views/HomeView.swift` (кнопки: «Начать новый раунд»→courseSearch, «Быстрый старт без выбора поля»→roundSetup)
- Modify: `ios/SmartGolfCaddy/Views/RoundSetupView.swift` + `RoundSetupViewModel.swift` (потребление selectedCourse)
- Modify: `ios/project.yml` (NSLocationWhenInUseUsageDescription + GOOGLE_PLACES_IOS_KEY в Info.plist из xcconfig)
- Modify: `ios/Config/Local.xcconfig.example` (+GOOGLE_PLACES_IOS_KEY placeholder)
- Test: `ios/SmartGolfCaddyTests/CoursesServiceTests.swift`

**Interfaces:**
- Produces:
  - `struct CourseResult: Equatable, Identifiable { placeId, name, vicinity, rating: Double?, userRatingsTotal: Int?, lat, lng, distanceKm: Double }` (id=placeId)
  - `enum CourseFetchError: LocalizedError { case config, network(String), denied(String), quota, invalid, http(Int) }` — errorDescription по-русски (тексты из courses.ts: «API ключ Google Places не настроен», «Нет связи с серверами Google», «Доступ к Places API (New) запрещён», «Превышен лимит запросов к Places API», «Некорректный запрос к Places API»)
  - `CoursesService.findNearby(lat:lng:) async throws -> [CourseResult]`, `.searchByText(_:biasLat:biasLng:) async throws -> [CourseResult]`; init для тестов с инжектируемым `transport: (URLRequest) async throws -> (Data, URLResponse)`; ключ читается из `Bundle.main.object(forInfoDictionaryKey: "GooglePlacesAPIKey")`
  - `GeolocationService` (NSObject, CLLocationManagerDelegate): `request(onUpdate: @escaping (Double, Double) -> Void, onError: @escaping (String) -> Void)` — when-in-use; колбэки на main; ошибки по-русски («Доступ к геолокации запрещён. Разрешите его в Настройках.», «Не удалось определить местоположение»)
  - `AppStore.selectedCourse: CourseResult?`
  - `CourseSearchView()`: строка поиска (debounce 400мс, ≥2 символа — текстовый поиск с bias; <2 — локальный фильтр nearby), кнопка «Использовать „<текст>“» / «Указать поле вручную / пропустить» → `store.selectedCourse = nil`, `store.prefillCourseName = <текст или nil>`, push(.roundSetup); карточки полей (имя, адрес, рейтинг ★, дистанция км) → selectedCourse=course + push(.roundSetup)
  - RoundSetup: если `store.selectedCourse != nil` — карточка поля (имя, адрес · N км, кнопка «Сменить поле» → pop назад) вместо TextField; иначе TextField с префиллом prefillCourseName; на создании courseId = selectedCourse?.placeId ?? "custom-<UUID>", courseName = selectedCourse?.name ?? effectiveName; при уходе с экрана setup selectedCourse/prefill очищаются (onDisappear после успешного создания — очистка в момент создания)

**РУЧНОЙ ШАГ ПОЛЬЗОВАТЕЛЯ (контроллер запросит при исполнении):** создать API-ключ для iOS в Google Cloud Console (проект smart-golf-caddy): APIs & Services → Credentials → Create credentials → API key → Restrict: iOS apps → bundle `com.dzhambulat.smartgolfcaddy`; API restrictions → Places API (New). Ключ → `ios/Config/Local.xcconfig`: `GOOGLE_PLACES_IOS_KEY = <ключ>`. Без ключа экран показывает «API ключ Google Places не настроен» — это валидное состояние для сборки/ревью; живой поиск проверяется на приёмке.

- [ ] **Step 1: Падающие тесты (транспорт-инжект, парсинг, ошибки, haversine)**

```swift
// ios/SmartGolfCaddyTests/CoursesServiceTests.swift
import XCTest
@testable import SmartGolfCaddy

final class CoursesServiceTests: XCTestCase {

    private func makeService(
        status: Int = 200,
        body: String,
        apiKey: String? = "test-key",
        captured: ((URLRequest) -> Void)? = nil
    ) -> CoursesService {
        CoursesService(apiKey: apiKey) { request in
            captured?(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
            )!
            return (body.data(using: .utf8)!, response)
        }
    }

    func testFindNearbyParsesPlaces() async throws {
        let body = """
        {"places":[{"id":"p1","displayName":{"text":"Сколково Гольф"},"formattedAddress":"Москва",
        "rating":4.7,"userRatingCount":120,"location":{"latitude":55.68,"longitude":37.38}}]}
        """
        let service = makeService(body: body)
        let results = try await service.findNearby(lat: 55.7, lng: 37.4)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].placeId, "p1")
        XCTAssertEqual(results[0].name, "Сколково Гольф")
        XCTAssertEqual(results[0].rating, 4.7)
        XCTAssertEqual(results[0].distanceKm, 2.5, accuracy: 1.5)  // haversine ~2-3 км
    }

    func testMissingKeyThrowsConfig() async {
        let service = makeService(body: "{}", apiKey: nil)
        do {
            _ = try await service.findNearby(lat: 1, lng: 1)
            XCTFail("ожидали ошибку")
        } catch let error as CourseFetchError {
            XCTAssertEqual(error.errorDescription, "API ключ Google Places не настроен")
        } catch { XCTFail("не тот тип") }
    }

    func testDeniedMapsTo403() async {
        let service = makeService(status: 403, body: #"{"error":{"message":"key restricted"}}"#)
        do {
            _ = try await service.findNearby(lat: 1, lng: 1)
            XCTFail("ожидали ошибку")
        } catch let error as CourseFetchError {
            if case .denied(let detail) = error {
                XCTAssertTrue(detail.contains("key restricted"))
            } else { XCTFail("не denied: \(error)") }
        } catch { XCTFail("не тот тип") }
    }

    func testSearchByTextSendsQueryAndBias() async throws {
        var sentBody: [String: Any] = [:]
        let service = makeService(body: #"{"places":[]}"#) { request in
            if let data = request.httpBody {
                sentBody = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            }
        }
        _ = try await service.searchByText("гольф", biasLat: 55.7, biasLng: 37.4)
        XCTAssertEqual(sentBody["textQuery"] as? String, "гольф")
        XCTAssertNotNil(sentBody["locationBias"])
    }
}
```

- [ ] **Step 2: RED.**

- [ ] **Step 3: Реализация**

```swift
// ios/SmartGolfCaddy/Models/Course.swift
import Foundation

struct CourseResult: Equatable, Identifiable {
    let placeId: String
    let name: String
    let vicinity: String
    let rating: Double?
    let userRatingsTotal: Int?
    let lat: Double
    let lng: Double
    let distanceKm: Double
    var id: String { placeId }
}
```

```swift
// ios/SmartGolfCaddy/Services/CoursesService.swift
// Порт src/services/courses.ts — Places API (New), REST. Ключ отдельный,
// с iOS-bundle-restriction (веб-ключ с HTTP-referrer здесь не работает).
import Foundation

enum CourseFetchError: LocalizedError {
    case config
    case network(String)
    case denied(String)
    case quota
    case invalid
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .config: return "API ключ Google Places не настроен"
        case .network: return "Нет связи с серверами Google"
        case .denied: return "Доступ к Places API (New) запрещён"
        case .quota: return "Превышен лимит запросов к Places API"
        case .invalid: return "Некорректный запрос к Places API"
        case .http(let code): return "Places API HTTP \(code)"
        }
    }
}

final class CoursesService: @unchecked Sendable {
    static let shared = CoursesService(
        apiKey: Bundle.main.object(forInfoDictionaryKey: "GooglePlacesAPIKey") as? String
    )

    private let apiKey: String?
    private let transport: (URLRequest) async throws -> (Data, URLResponse)

    init(apiKey: String?,
         transport: @escaping (URLRequest) async throws -> (Data, URLResponse) = { request in
             try await URLSession.shared.data(for: request)
         }) {
        // Пустая строка/плейсхолдер = ключа нет.
        let cleaned = apiKey?.trimmingCharacters(in: .whitespaces)
        self.apiKey = (cleaned?.isEmpty ?? true) || cleaned == "placeholder" ? nil : cleaned
        self.transport = transport
    }

    private struct PlacesResponse: Decodable {
        struct Place: Decodable {
            struct DisplayName: Decodable { let text: String? }
            struct Location: Decodable { let latitude: Double?; let longitude: Double? }
            let id: String?
            let displayName: DisplayName?
            let formattedAddress: String?
            let rating: Double?
            let userRatingCount: Int?
            let location: Location?
        }
        struct APIError: Decodable { let message: String? }
        let places: [Place]?
        let error: APIError?
    }

    private static let fieldMask = [
        "places.id", "places.displayName", "places.formattedAddress",
        "places.rating", "places.userRatingCount", "places.location",
    ].joined(separator: ",")

    func findNearby(lat: Double, lng: Double) async throws -> [CourseResult] {
        let body: [String: Any] = [
            "includedTypes": ["golf_course"],
            "maxResultCount": 20,
            "locationRestriction": [
                "circle": ["center": ["latitude": lat, "longitude": lng], "radius": 20000.0],
            ],
        ]
        return try await request(
            url: "https://places.googleapis.com/v1/places:searchNearby",
            body: body, originLat: lat, originLng: lng
        )
    }

    func searchByText(_ query: String, biasLat: Double?, biasLng: Double?) async throws -> [CourseResult] {
        var body: [String: Any] = [
            "textQuery": query,
            "includedType": "golf_course",
            "maxResultCount": 20,
        ]
        if let biasLat, let biasLng {
            body["locationBias"] = [
                "circle": ["center": ["latitude": biasLat, "longitude": biasLng], "radius": 50000.0],
            ]
        }
        return try await request(
            url: "https://places.googleapis.com/v1/places:searchText",
            body: body, originLat: biasLat, originLng: biasLng
        )
    }

    private func request(url: String, body: [String: Any],
                         originLat: Double?, originLng: Double?) async throws -> [CourseResult] {
        guard let apiKey else { throw CourseFetchError.config }
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(Self.fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            throw CourseFetchError.network(String(describing: error))
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 {
            let detail = (try? JSONDecoder().decode(PlacesResponse.self, from: data))?.error?.message ?? ""
            switch status {
            case 403: throw CourseFetchError.denied(detail)
            case 429: throw CourseFetchError.quota
            case 400: throw CourseFetchError.invalid
            default: throw CourseFetchError.http(status)
            }
        }

        let parsed = try JSONDecoder().decode(PlacesResponse.self, from: data)
        return (parsed.places ?? []).map { place in
            let placeLat = place.location?.latitude ?? originLat ?? 0
            let placeLng = place.location?.longitude ?? originLng ?? 0
            let distanceKm: Double
            if let originLat, let originLng {
                distanceKm = (Self.haversineMetres(originLat, originLng, placeLat, placeLng) / 100).rounded() / 10
            } else {
                distanceKm = 0
            }
            return CourseResult(
                placeId: place.id ?? "",
                name: place.displayName?.text ?? "Поле для гольфа",
                vicinity: place.formattedAddress ?? "",
                rating: place.rating,
                userRatingsTotal: place.userRatingCount,
                lat: placeLat, lng: placeLng,
                distanceKm: distanceKm
            )
        }
    }

    static func haversineMetres(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        let r = 6371000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
```

```swift
// ios/SmartGolfCaddy/Services/GeolocationService.swift
// Обёртка CLLocationManager (when-in-use). Колбэки — на main.
import CoreLocation
import Foundation

final class GeolocationService: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = GeolocationService()

    private let manager = CLLocationManager()
    private var onUpdate: ((Double, Double) -> Void)?
    private var onError: ((String) -> Void)?

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request(onUpdate: @escaping (Double, Double) -> Void,
                 onError: @escaping (String) -> Void) {
        self.onUpdate = onUpdate
        self.onError = onError
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            DispatchQueue.main.async {
                onError("Доступ к геолокации запрещён. Разрешите его в Настройках.")
            }
        default:
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            DispatchQueue.main.async { [weak self] in
                self?.onError?("Доступ к геолокации запрещён. Разрешите его в Настройках.")
            }
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(location.coordinate.latitude, location.coordinate.longitude)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?("Не удалось определить местоположение")
        }
    }
}
```

`AppStore.swift` — добавить поля:

```swift
    /// Поле, выбранное в поиске — потребляется RoundSetup и очищается им.
    var selectedCourse: CourseResult?
    /// Префилл названия при «Использовать „текст“» из поиска.
    var prefillCourseName: String?
```

```swift
// ios/SmartGolfCaddy/ViewModels/CourseSearchViewModel.swift
import Foundation
import Observation

@Observable
@MainActor
final class CourseSearchViewModel {
    var searchText = ""
    var nearby: [CourseResult] = []
    var textResults: [CourseResult]?
    var loading = false
    var errorMessage: String?
    var geoDenied = false

    private var lat: Double?
    private var lng: Double?
    private var searchTask: Task<Void, Never>?

    var visible: [CourseResult] {
        if let textResults { return textResults }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty { return nearby }
        return nearby.filter {
            $0.name.lowercased().contains(query) || $0.vicinity.lowercased().contains(query)
        }
    }

    func start() {
        GeolocationService.shared.request(
            onUpdate: { [weak self] lat, lng in
                guard let self else { return }
                self.lat = lat
                self.lng = lng
                Task { await self.loadNearby() }
            },
            onError: { [weak self] message in
                self?.geoDenied = true
                self?.errorMessage = message
            }
        )
    }

    func loadNearby() async {
        guard let lat, let lng else { return }
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            nearby = try await CoursesService.shared.findNearby(lat: lat, lng: lng)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Debounce 400мс; < 2 символов — сброс на локальный фильтр.
    func searchChanged() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else {
            textResults = nil
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            self.loading = true
            defer { self.loading = false }
            do {
                self.textResults = try await CoursesService.shared.searchByText(
                    query, biasLat: self.lat, biasLng: self.lng
                )
            } catch {
                self.textResults = []
            }
        }
    }
}
```

```swift
// ios/SmartGolfCaddy/Views/CourseSearchView.swift — заменить заглушку целиком
import SwiftUI

struct CourseSearchView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppStore.self) private var store
    @State private var model = CourseSearchViewModel()

    var body: some View {
        VStack(spacing: 8) {
            searchField
            DSButton(
                title: model.searchText.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "Указать поле вручную / пропустить"
                    : "Использовать «\(model.searchText.trimmingCharacters(in: .whitespaces))»",
                style: .secondary
            ) {
                store.selectedCourse = nil
                let query = model.searchText.trimmingCharacters(in: .whitespaces)
                store.prefillCourseName = query.isEmpty ? nil : query
                router.push(.roundSetup)
            }
            .padding(.horizontal, DS.screenPadding)
            content
        }
        .background(DSColor.surface)
        .navigationTitle("Поиск полей")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.start() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DSColor.onSurfaceVariant)
            TextField("Поиск полей или городов", text: $model.searchText)
                .font(DSFont.bodyMD)
                .onChange(of: model.searchText) { _, _ in model.searchChanged() }
        }
        .padding(12)
        .background(DSColor.surfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
        .padding(.horizontal, DS.screenPadding)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let message = model.errorMessage, model.visible.isEmpty {
            VStack(spacing: 12) {
                Text(message)
                    .font(DSFont.bodyMD)
                    .foregroundStyle(DSColor.error)
                    .multilineTextAlignment(.center)
                if !model.geoDenied {
                    DSButton(title: "Повторить", style: .secondary) {
                        Task { await model.loadNearby() }
                    }
                    .padding(.horizontal, 64)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(DS.screenPadding)
        } else if model.loading && model.visible.isEmpty {
            ProgressView("Ищем поля рядом...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.visible.isEmpty {
            Text("Поля не найдены. Попробуйте другой запрос или укажите поле вручную.")
                .font(DSFont.bodyMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(DS.screenPadding)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.visible) { course in
                        courseCard(course)
                    }
                }
                .padding(DS.screenPadding)
            }
        }
    }

    private func courseCard(_ course: CourseResult) -> some View {
        Button {
            store.selectedCourse = course
            store.prefillCourseName = nil
            router.push(.roundSetup)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "flag.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(DSColor.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.name)
                        .font(DSFont.bodyMD)
                        .foregroundStyle(DSColor.onSurface)
                        .lineLimit(1)
                    Text(course.vicinity)
                        .font(DSFont.labelMD)
                        .foregroundStyle(DSColor.onSurfaceVariant)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        if let rating = course.rating {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                .font(DSFont.labelMD)
                                .foregroundStyle(DSColor.onSurfaceVariant)
                        }
                        Text("\(String(format: "%.1f", course.distanceKm)) км")
                            .font(DSFont.labelMD)
                            .foregroundStyle(DSColor.onSurfaceVariant)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(DSColor.primary)
            }
            .padding(12)
            .background(DSColor.surfaceContainerLowest)
            .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: DS.cornerRadius).stroke(DSColor.outlineVariant.opacity(0.25)))
        }
        .buttonStyle(.plain)
    }
}
```

`HomeView.swift` — кнопочный блок заменить:

```swift
                VStack(spacing: 12) {
                    DSButton(title: "Начать новый раунд", icon: "plus") {
                        router.push(.courseSearch)
                    }
                    DSButton(title: "Быстрый старт без выбора поля", icon: "bolt", style: .secondary) {
                        store.prefillCourseName = nil
                        store.selectedCourse = nil
                        router.push(.roundSetup)
                    }
                }
```

(и добавить `@Environment(AppStore.self) private var store`, если ещё не был.)

`RoundSetupViewModel` — добавить поля и метод (createRound меняет courseId):

```swift
    var selectedPlaceId: String?
    var selectedVicinity: String = ""
    var selectedDistanceKm: Double = 0

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
```

и в `createRound` заменить courseId-строку: `courseId: selectedPlaceId ?? "custom-\(UUID().uuidString)"`.

`RoundSetupView` — `.task { model.adopt(store: store) }` (добавить `@Environment(AppStore.self) private var store`); в `nameSection`: если `model.selectedPlaceId != nil` — вместо TextField карточка выбранного поля:

```swift
            VStack(alignment: .leading, spacing: 6) {
                Text(model.courseName)
                    .font(DSFont.titleLG)
                    .foregroundStyle(DSColor.onSurface)
                Text("\(model.selectedVicinity) · \(String(format: "%.1f", model.selectedDistanceKm)) км")
                    .font(DSFont.labelLG)
                    .foregroundStyle(DSColor.onSurfaceVariant)
                Button("Сменить поле") {
                    router.replaceLast(.courseSearch)
                }
                .font(DSFont.labelLG)
                .foregroundStyle(DSColor.primary)
                .frame(minHeight: DS.touchTarget)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DSColor.surfaceContainerLowest)
            .clipShape(RoundedRectangle(cornerRadius: DS.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: DS.cornerRadius).stroke(DSColor.outlineVariant.opacity(0.25)))
```

(`router` в RoundSetupView уже есть из 2а.)

`ios/project.yml` в `targets.SmartGolfCaddy.info.properties` добавить:

```yaml
        NSLocationWhenInUseUsageDescription: "Геолокация нужна, чтобы найти гольф-поля рядом с вами."
        GooglePlacesAPIKey: "$(GOOGLE_PLACES_IOS_KEY)"
```

`ios/Config/Local.xcconfig.example` — добавить строку `GOOGLE_PLACES_IOS_KEY = placeholder` (и исполнителю: добавить ту же строку в РЕАЛЬНЫЙ Local.xcconfig, чтобы сборка шла; настоящий ключ вставит пользователь на приёмке).

- [ ] **Step 4: GREEN + сборка + скриншот** (экран поиска: без ключа — «API ключ Google Places не настроен» + кнопка ручного ввода работает; это ОК).

- [ ] **Step 5: Commit**

```bash
git add ios/SmartGolfCaddy ios/SmartGolfCaddyTests/CoursesServiceTests.swift ios/project.yml ios/Config/Local.xcconfig.example
git commit -m "feat(ios): course search — Places API (New), geolocation, setup integration"
```

---

### Task 6: Hardening из беклога + email в PlayerInfo

**Files:**
- Modify: `ios/SmartGolfCaddy/Services/AuthService.swift` (+currentUserEmail)
- Modify: `ios/SmartGolfCaddy/ViewModels/RoundSetupViewModel.swift` (email в hostInfo + тест effectiveName)
- Modify: `ios/SmartGolfCaddy/Services/RoundsService.swift` (subscribeToRound: недекодируемый док → onError)
- Modify: `ios/SmartGolfCaddy/Services/ShotQueue.swift` (static monitor → instance-поля)
- Modify: `ios/SmartGolfCaddy/Views/RoundResultsView.swift` («Новый раунд» → router.resetTo(.roundSetup))
- Modify: `ios/SmartGolfCaddy/Views/HoleTrackerView.swift` + Create: `ios/SmartGolfCaddy/Views/Components/FlowLayoutCompat.swift` (вынос компонента)
- Test: `ios/SmartGolfCaddyTests/ScoringTests.swift` (+3: mid-round AS и N UP, totalScore tie-break, clubUsage multi-round), `ios/SmartGolfCaddyTests/RoundSetupViewModelTests.swift` (новый: effectiveName)

**Шаги (каждый — точечная правка, все с кодом):**

- [ ] **Step 1: email.** AuthService: `static var currentUserEmail: String? { Auth.auth().currentUser?.email }`. RoundSetupViewModel: `email: AuthService.currentUserEmail` вместо nil + комментарий «паритет с вебом: user.email ?? ''» (пустую строку не шлём — nil опускается, сервер имеет Auth-lookup fallback).

- [ ] **Step 2: subscribeToRound onError на битом доке.** В замыкании листенера RoundsService: ветка «snapshot есть, но Round(id:data:) == nil» → `onError(NSError(domain: "SmartGolfCaddy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Данные раунда повреждены"]))` (вместо молчания). Тестов нет (Firebase-путь) — компиляция + смоук.

- [ ] **Step 3: ShotQueue monitor.** `private static var monitor/pathMonitorOnline` → инстанс-поля `private var monitor: NWPathMonitor?` и `private var online = true`; `isOnline`-замыкание shared-инициализатора заменить на чтение инстансного поля: shared создаётся с `isOnline: { ShotQueue.shared.online }`?? — цикл в init; РЕШЕНИЕ: сделать `online` internal private(set) и дефолт isOnline-замыкание в init убрать: в init хранить переданный isOnline как optional; в recordShotQueued использовать `isOnlineOverride?() ?? online`. Тесты передают isOnline как раньше (override); прод — nil → инстансное поле, обновляемое монитором.

- [ ] **Step 4: проверка навигации Results.** Убедиться, что RoundResultsView зовёт `router.startNewRound()`/`router.goHome()` (сделано в T2) и прямых `popToRoot()+push` каскадов не осталось (grep по файлу).

- [ ] **Step 5: FlowLayoutCompat** — вырезать из HoleTrackerView.swift в `Views/Components/FlowLayoutCompat.swift` (код без изменений).

- [ ] **Step 6: Тесты.**

```swift
// в ScoringTests:
    func testMatchPlayMidRoundLabels() {
        // 3 лунки, сыграна 1: A выиграл → "1 UP" (не закрыто); ничья → "AS"
        func round(aCount: Int, bCount: Int) -> Round {
            makeRound(
                holes: [
                    hole(1, par: 4, shots: [
                        "a": ["count": aCount, "clubs": Array(repeating: "7i", count: aCount)],
                        "b": ["count": bCount, "clubs": Array(repeating: "7i", count: bCount)],
                    ]),
                    hole(2, par: 4), hole(3, par: 4),
                ],
                players: [
                    "a": ["name": "А", "avatar": "", "totalScore": 0, "scoreDiff": 0],
                    "b": ["name": "Б", "avatar": "", "totalScore": 0, "scoreDiff": 0],
                ],
                playerIds: ["a", "b"], playMode: "match"
            )
        }
        XCTAssertEqual(Scoring.matchPlayStatus(round: round(aCount: 3, bCount: 4), uidA: "a", uidB: "b").label, "1 UP")
        XCTAssertEqual(Scoring.matchPlayStatus(round: round(aCount: 4, bCount: 4), uidA: "a", uidB: "b").label, "AS")
    }

    func testLeaderboardTotalScoreTieBreak() {
        // Равный diff, разный total: меньше ударов — выше
        let round = makeRound(
            holes: [
                hole(1, par: 4, shots: ["a": ["count": 4, "clubs": ["7i", "7i", "PW", "Putter"]]]),
                hole(2, par: 3, shots: ["b": ["count": 3, "clubs": ["7i", "PW", "Putter"]]]),
            ],
            players: [
                "a": ["name": "А", "avatar": "", "totalScore": 0, "scoreDiff": 0],
                "b": ["name": "Б", "avatar": "", "totalScore": 0, "scoreDiff": 0],
            ],
            playerIds: ["a", "b"]
        )
        XCTAssertEqual(Scoring.leaderboard(round: round).map(\.uid), ["b", "a"])
    }

    func testClubUsageAcrossRounds() {
        let r1 = makeRound(holes: [hole(1, par: 4, shots: ["u1": ["count": 1, "clubs": ["Driver"]]])])
        let r2 = makeRound(holes: [hole(1, par: 4, shots: ["u1": ["count": 2, "clubs": ["Driver", "PW"]]])])
        let usage = Scoring.clubUsage(rounds: [r1, r2], userId: "u1")
        XCTAssertEqual(usage.first?.club, "Driver")
        XCTAssertEqual(usage.first?.count, 2)
        XCTAssertEqual(usage.first?.percent, 67)
    }
```

```swift
// ios/SmartGolfCaddyTests/RoundSetupViewModelTests.swift
import XCTest
@testable import SmartGolfCaddy

final class RoundSetupViewModelTests: XCTestCase {
    @MainActor
    func testEffectiveNameTrimAndFallback() {
        let model = RoundSetupViewModel()
        model.courseName = "   "
        XCTAssertEqual(model.effectiveName, "Поле для гольфа")
        model.courseName = "  Сколково  "
        XCTAssertEqual(model.effectiveName, "Сколково")
    }
}
```

- [ ] **Step 7: GREEN (все тесты) + build. Commit**

```bash
git add ios/SmartGolfCaddy ios/SmartGolfCaddyTests
git commit -m "fix(ios): backlog hardening — host email, corrupt-round error, queue monitor, resetTo, tests"
```

---

### Task 7: Иконка приложения

**Files:**
- Create: `ios/scripts/gen-appicon.swift` (генератор, запускается `swift ios/scripts/gen-appicon.swift`)
- Create: `ios/SmartGolfCaddy/Resources/Assets.xcassets/` (Contents.json + AppIcon.appiconset с icon-1024.png)
- Modify: `ios/project.yml` (ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon в settings.base)

**Дизайн иконки:** фон — вертикальный градиент primary-container `#1B5E20` → primary `#00450D`; по центру белый символ гольф-флага (флажок-треугольник на флагштоке + лунка-эллипс внизу), нарисованный CoreGraphics-путями; скругление не рисуем (iOS маскирует сам).

- [ ] **Step 1: Скрипт**

```swift
// ios/scripts/gen-appicon.swift
// Однократный генератор иконки: swift ios/scripts/gen-appicon.swift
import AppKit
import CoreGraphics

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Градиентный фон
let colors = [
    NSColor(red: 0x1B / 255, green: 0x5E / 255, blue: 0x20 / 255, alpha: 1).cgColor,
    NSColor(red: 0x00 / 255, green: 0x45 / 255, blue: 0x0D / 255, alpha: 1).cgColor,
]
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: size),
                       end: CGPoint(x: size, y: 0),
                       options: [])

ctx.setFillColor(NSColor.white.cgColor)
ctx.setStrokeColor(NSColor.white.cgColor)

// Флагшток
let poleX = 430.0
ctx.setLineWidth(34)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: poleX, y: 260))
ctx.addLine(to: CGPoint(x: poleX, y: 790))
ctx.strokePath()

// Флажок (треугольник вправо)
ctx.move(to: CGPoint(x: poleX + 17, y: 780))
ctx.addLine(to: CGPoint(x: poleX + 320, y: 655))
ctx.addLine(to: CGPoint(x: poleX + 17, y: 530))
ctx.closePath()
ctx.fillPath()

// Лунка (эллипс под флагштоком)
ctx.fillEllipse(in: CGRect(x: poleX - 150, y: 195, width: 300, height: 80))

image.unlockFocus()

let tiff = image.tiffRepresentation!
let bitmap = NSBitmapImageRep(data: tiff)!
let png = bitmap.representation(using: .png, properties: [:])!
let out = "ios/SmartGolfCaddy/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
try! FileManager.default.createDirectory(atPath: (out as NSString).deletingLastPathComponent,
                                         withIntermediateDirectories: true)
try! png.write(to: URL(fileURLWithPath: out))
print("written: \(out)")
```

- [ ] **Step 2: Каталог.** `Assets.xcassets/Contents.json`: `{"info":{"author":"xcode","version":1}}`; `AppIcon.appiconset/Contents.json`:

```json
{
  "images": [
    {"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}
  ],
  "info": {"author": "xcode", "version": 1}
}
```

Запустить `swift ios/scripts/gen-appicon.swift` (из корня репо); проверить PNG появился (~15-40 KB); `sips -g pixelWidth` = 1024.

- [ ] **Step 3: project.yml** — в `targets.SmartGolfCaddy.settings.base`: `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`. `xattr -c` на png.

- [ ] **Step 4: Сборка + установка на симулятор** — на домашнем экране симулятора иконка зелёная с флагом (`xcrun simctl io booted screenshot` после Home-жеста не обязателен; достаточно установки без ошибок ASSETCATALOG). Тесты не затронуты, но прогнать test.sh.

- [ ] **Step 5: Commit**

```bash
git add ios/scripts/gen-appicon.swift "ios/SmartGolfCaddy/Resources/Assets.xcassets" ios/project.yml
git commit -m "feat(ios): app icon — flag on fairway gradient, generated by script"
```

---

### Task 8: Сквозная сборка, доки, подготовка приёмки

- [ ] **Step 1: Полный прогон** — `./ios/scripts/test.sh` (все зелёные), `./ios/scripts/build.sh`, веб-проверки (`npm run test:run`, `npx tsc --noEmit`) — Task 1 трогал веб.
- [ ] **Step 2: CLAUDE.md** — в iOS-прозу добавить (append-стиль, 4-6 строк): таббар (Раунды/История/Профиль), UsersService/CoursesService/GeolocationService, штраф (Clubs.penaltyId ↔ PENALTY_ID — SYNC), GooglePlacesAPIKey из Local.xcconfig (GOOGLE_PLACES_IOS_KEY).
- [ ] **Step 3: SETUP.md** — в секцию iOS пункт: ключ Google Places для iOS (инструкция создания с bundle-restriction, куда вписать).
- [ ] **Step 4: Commit** `docs: phase 2b — architecture notes and Places key setup`.
- [ ] **Step 5 (контроллер): установка на симулятор+iPhone, запрос пользователю:** создать Places-ключ (инструкция из SETUP.md), вставить в Local.xcconfig (или прислать контроллеру защищённо НЕ в чат — лучше пользователь вставляет сам и говорит «готово»), пересборка, приёмка: таббар, история, профиль-статистика, сумка (toggle/дистанции/кастомная/порядок), поиск полей (гео-разрешение → список → выбор → setup с карточкой поля), штраф в трекере, иконка.
