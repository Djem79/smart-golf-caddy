# iOS Phase 3c — Apple Watch Companion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Приложение для Apple Watch, с которого можно вести раунд, не доставая телефон: счёт лунки, выбор клюшки, запись ударов, переход между лунками, дистанция до грина. Часы самодостаточны офлайн — пишут в собственную очередь и синхронизируются, когда телефон рядом.

**Architecture (решение владельца 2026-08-20):** гибрид. Firestore на watchOS не поставляется (в `Package.swift` firebase-ios-sdk зависимость включена только для iOS/tvOS/macOS/Catalyst), GoogleSignIn для watchOS не существует, App Check-компонент недоступен — поэтому часы **не** обращаются к Firebase. Телефон остаётся единственным клиентом Firebase; обмен идёт через `WatchConnectivity`:

```
iPhone (Firebase)  ──applicationContext──▶  Watch (UI + очередь + GPS)
                   ◀──transferUserInfo────  (записанные удары)
```

Часы получают снимок активного раунда (лунки, пары, счёт, сумка, метки гринов), пишут удары в свою durable-очередь и отдают их телефону; телефон кладёт их в существующий `ShotQueue`, который уже умеет идемпотентную отправку и офлайн. Собственный GPS часов считает дистанцию до грина по полученным меткам — без телефона и без сети.

**Tech Stack:** watchOS 10+ target (XcodeGen), SwiftUI, WatchConnectivity (WCSession), CoreLocation (watchOS).

**Spec:** `docs/superpowers/specs/2026-08-17-ios-app-design.md` (нативные фичи). Исследование осуществимости: `.superpowers/sdd/2026-08-18-ios-phase2c-gps-rangefinder/research-watch.md`. Анализ рынка (что считается достаточным на часах): `.superpowers/sdd/2026-08-18-ios-phase2c-gps-rangefinder/research-market.md`.

## Global Constraints

- Сборка/тесты iOS — только `./ios/scripts/test.sh` / `./ios/scripts/build.sh`. Для watch-таргета скрипты дополняются (Task 1); прямой xcodebuild запрещён.
- **На watch-таргете НЕТ Firebase и GoogleSignIn** — ни одного импорта. Нарушение = архитектурная ошибка (эти SDK физически не собираются под watchOS).
- Общий код (`Models/*.swift`, включая Scoring/Score/Clubs/GreenMarks) добавляется в watch-таргет как есть — он Foundation-only. Дублировать модели запрещено.
- Watch-таргет: bundle id `com.dzhambulat.smartgolfcaddy.watchkitapp`, deployment watchOS 10.0, встраивается в iOS-приложение.
- Обмен сообщениями — единый контракт (Task 2), сериализация `[String: Any]` (WatchConnectivity не умеет Codable напрямую); версия протокола в каждом сообщении (`v: 1`), незнакомые версии игнорируются.
- Русский UI дословно; SF Symbols; на часах — крупные тапабельные зоны (минимум 44×44 pt по HIG watchOS).
- Тесты: логика (кодирование сообщений, очередь часов, дистанция) — юнит-тестами в отдельном тест-таргете watch или в общем (решается в Task 1); UI на часах — ручная проверка на симуляторе.
- Коммит после каждой задачи.

---

### Task 1: watchOS-таргет и общий код (инфраструктура)

**Files:**
- Modify: `ios/project.yml` (watch app target + встраивание + общий Models)
- Create: `ios/SmartGolfCaddyWatch/App/WatchApp.swift`, `ios/SmartGolfCaddyWatch/Views/WatchRootView.swift`
- Modify: `ios/scripts/build.sh`, `ios/scripts/test.sh` (сборка обоих таргетов)
- Create: `ios/SmartGolfCaddyWatchTests/SmokeTests.swift`

**Interfaces:**
- Produces: собираемое watch-приложение (заглушка «Раунд не начат»), общий доступ к `Models/*`; команда сборки часов.

**Ключевой риск:** встраивание watch-app под Xcode 26 (XcodeGen issue #1613 — исправлено в 2.45.3, у нас 2.46.0, но подтвердить фактической сборкой). Если `embed` не работает — фолбэк: `dependencies: [target: SmartGolfCaddyWatch, embed: true, codeSign: true]` с явным `destinationFilters`, либо ручная проверка сгенерированного `.pbxproj`.

- [ ] **Step 1: Добавить таргет в `ios/project.yml`**

```yaml
  SmartGolfCaddyWatch:
    type: application
    platform: watchOS
    deploymentTarget: "10.0"
    sources:
      - SmartGolfCaddyWatch
      - path: SmartGolfCaddy/Models          # общий домен, Foundation-only
      - path: SmartGolfCaddy/DesignSystem    # цвета/шрифты/токены
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.dzhambulat.smartgolfcaddy.watchkitapp
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: $(DEV_TEAM)
        GENERATE_INFOPLIST_FILE: NO
        WATCHOS_DEPLOYMENT_TARGET: "10.0"
    info:
      path: SmartGolfCaddyWatch/Info.plist
      properties:
        CFBundleDisplayName: Golf Caddy
        WKApplication: true
        WKCompanionAppBundleIdentifier: com.dzhambulat.smartgolfcaddy
        NSLocationWhenInUseUsageDescription: "Геолокация нужна, чтобы показывать дистанцию до грина и мерить длину ударов."
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
```

и в iOS-таргете:

```yaml
    dependencies:
      - target: SmartGolfCaddyWatch
        embed: true
```

- [ ] **Step 2: Скелет приложения часов**

```swift
// ios/SmartGolfCaddyWatch/App/WatchApp.swift
import SwiftUI

@main
struct SmartGolfCaddyWatchApp: App {
    var body: some Scene {
        WindowGroup { WatchRootView() }
    }
}
```

```swift
// ios/SmartGolfCaddyWatch/Views/WatchRootView.swift
import SwiftUI

struct WatchRootView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.golf")
                .font(.system(size: 28))
                .foregroundStyle(DSColor.primary)
            Text("Раунд не начат")
                .font(DSFont.labelLG)
                .multilineTextAlignment(.center)
            Text("Начните раунд на телефоне")
                .font(DSFont.labelMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
```

Примечание: `DSFont` использует бандл-шрифт Playfair Display; на часах он может быть недоступен (ресурс лежит в iOS-таргете). В этой задаче проверить: если `.custom` не резолвится, добавить `SmartGolfCaddy/Resources/Fonts` в sources watch-таргета и `UIAppFonts` в его Info.plist; если и это не сработает — создать `DSFontWatch` с системным шрифтом и задокументировать отклонение.

- [ ] **Step 3: Скрипты сборки**

`ios/scripts/build.sh` и `test.sh` дополнить сборкой часов (после основной):

```bash
xcodebuild -project SmartGolfCaddy.xcodeproj -scheme SmartGolfCaddyWatch \
  -destination "platform=watchOS Simulator,name=${WATCH_SIM_NAME:-Apple Watch Series 11 (46mm)}" \
  -derivedDataPath "$DD" build
```

(в test.sh — только сборка, если тест-таргет часов ещё не заведён).

- [ ] **Step 4: Проверка** — `./ios/scripts/build.sh` собирает оба таргета; установка на симулятор часов:

```bash
xcrun simctl boot "Apple Watch Series 11 (46mm)" 2>/dev/null
xcrun simctl install "Apple Watch Series 11 (46mm)" "$DD/Build/Products/Debug-watchsimulator/SmartGolfCaddyWatch.app"
xcrun simctl launch "Apple Watch Series 11 (46mm)" com.dzhambulat.smartgolfcaddy.watchkitapp
xcrun simctl io "Apple Watch Series 11 (46mm)" screenshot /tmp/watch.png
```
Скриншот — в отчёт. iOS-тесты не должны сломаться.

- [ ] **Step 5: Commit** — `feat(watch): watchOS target with shared domain models`

---

### Task 2: Канал связи телефон ↔ часы (TDD на кодировании)

**Files:**
- Create: `ios/SmartGolfCaddy/Services/WatchBridge.swift` (сторона iPhone)
- Create: `ios/SmartGolfCaddyWatch/Services/PhoneBridge.swift` (сторона часов)
- Create: `ios/SmartGolfCaddy/Models/WatchMessages.swift` (общий контракт, добавить в оба таргета)
- Test: `ios/SmartGolfCaddyTests/WatchMessagesTests.swift`

**Interfaces:**
- Produces:
  - `struct WatchRoundSnapshot: Equatable` — что телефон шлёт часам: `roundId`, `courseName`, `totalHoles`, `holes: [WatchHole]` (`number`, `par`, `distanceMeters`, `myShots: Int`), `clubs: [String]` (включённые из сумки, до 14), `greens: [Int: GreenMark]`, `activeHoleNumber`, `units` (`m`/`yd`), `updatedAt`
  - `struct WatchShotBatch: Equatable` — что часы шлют телефону: `roundId`, `entries: [WatchShotEntry]` (`holeNumber`, `clubs: [String]`, `recordedAt`)
  - Обе структуры: `init?(payload: [String: Any])` + `var payload: [String: Any]` c полем `v: 1`
  - `WatchBridge.shared` (iPhone): `activate()`, `send(snapshot:)` (через `updateApplicationContext`), `onShotBatch: ((WatchShotBatch) -> Void)?`
  - `PhoneBridge.shared` (Watch): `activate()`, `latestSnapshot: WatchRoundSnapshot?` (@Observable), `send(batch:)` (через `transferUserInfo` — доставляется гарантированно, в т.ч. позже), `isReachable`

- [ ] **Step 1: Падающие тесты кодирования** (round-trip обеих структур, отбрасывание чужой версии `v`, устойчивость к мусору).

- [ ] **Step 2: RED.**

- [ ] **Step 3: Реализация** — контракт в `WatchMessages.swift` (Foundation-only, добавляется в оба таргета); мосты на `WCSessionDelegate`. Правила: снапшот — `updateApplicationContext` (перезаписывается, всегда актуален); удары — `transferUserInfo` (очередь доставки, переживает выключенный телефон).

- [ ] **Step 4: GREEN + сборка обоих таргетов.**

- [ ] **Step 5: Commit** — `feat(watch): connectivity contract and bridges`

---

### Task 3: Интерфейс часов — лунка и запись ударов

**Files:**
- Create: `ios/SmartGolfCaddyWatch/ViewModels/WatchRoundViewModel.swift`
- Create: `ios/SmartGolfCaddyWatch/Views/WatchHoleView.swift`, `Views/WatchClubPicker.swift`
- Modify: `ios/SmartGolfCaddyWatch/Views/WatchRootView.swift` (маршрутизация: нет раунда / есть раунд)
- Test: `ios/SmartGolfCaddyWatchTests/WatchRoundViewModelTests.swift` (или общий тест-таргет — по итогам Task 1)

**Interfaces:**
- Produces: `WatchRoundViewModel` (`snapshot`, `holeNumber`, `shots: [String]` локально, `selectedClub`, `addShot()`, `removeShot()`, `nextHole()`, `previousHole()`, `pendingCount`); экраны: счёт лунки (крупная цифра, «+»/«−»), пикер клюшек (список с крупными строками), навигация лунок (свайп/кнопки), индикатор несинхронизированных ударов.

**UX-минимум по анализу рынка:** номер лунки и пар, счёт, кнопка добавления удара, выбор клюшки, дистанция до грина (Task 5), признак «не синхронизировано».

- [ ] **Step 1: Тесты VM** (добавление/удаление ударов не уходит в минус; смена лунки сохраняет локальные удары; счётчик несинхронизированных).
- [ ] **Step 2: RED → Step 3: Реализация → Step 4: GREEN + скриншоты симулятора часов.**
- [ ] **Step 5: Commit** — `feat(watch): hole screen, shot counter and club picker`

---

### Task 4: Очередь часов и приём на телефоне

**Files:**
- Create: `ios/SmartGolfCaddyWatch/Services/WatchShotQueue.swift`
- Modify: `ios/SmartGolfCaddy/Services/WatchBridge.swift` (приём батча → ShotQueue)
- Modify: `ios/SmartGolfCaddy/App/AppDelegate.swift` (активация моста)
- Test: `ios/SmartGolfCaddyWatchTests/WatchShotQueueTests.swift`

**Interfaces:**
- Produces: `WatchShotQueue` (файловая durable-очередь на часах: `enqueue`, `pending`, `markSent`, `flush(via:)`), приём на iPhone: батч → для каждой записи `ShotQueue.shared.recordShotQueued(roundId:holeIndex:targetUid:clubs:distances:)` (свой uid, дистанции — пустые: замер удара остаётся на телефоне).

**Инварианты:** идемпотентность (`recordShot` пишет весь массив клюшек лунки — повтор безопасен); часы не удаляют запись, пока телефон не подтвердил приём; при конфликте (телефон уже писал эту лунку) выигрывает последняя запись — то же поведение, что и в существующей очереди.

- [ ] **Step 1: Тесты очереди** (переживает перезапуск, дубликаты не плодятся, подтверждение удаляет запись).
- [ ] **Step 2: RED → Step 3: Реализация → Step 4: GREEN + сборка.**
- [ ] **Step 5: Commit** — `feat(watch): durable shot queue with phone handoff`

---

### Task 5: GPS на часах и дистанция до грина

**Files:**
- Create: `ios/SmartGolfCaddyWatch/Services/WatchLocationService.swift`
- Modify: `ios/SmartGolfCaddyWatch/ViewModels/WatchRoundViewModel.swift` (дистанция)
- Modify: `ios/SmartGolfCaddyWatch/Views/WatchHoleView.swift` (строка «До грина»)
- Test: расчёт дистанции переиспользует `Greens.distanceMeters` (уже покрыт тестами)

**Interfaces:**
- Produces: `WatchLocationService` (CoreLocation на watchOS, when-in-use, `lastFix: GeoFix?`, старт/стоп по появлению экрана лунки), `WatchRoundViewModel.greenDistanceMeters: Int?` (те же гейты: точность ≤25 м, возраст ≤90 с, диапазон 0…800 м, единицы из снапшота).

**Замечание:** метки гринов приходят в снапшоте с телефона — на часах их не отмечают (кнопка «Я на грине» остаётся на телефоне, чтобы не плодить источники записи).

- [ ] **Step 1: Реализация → Step 2: сборка + проверка на симуляторе часов с симуляцией локации → Step 3: Commit** — `feat(watch): on-wrist distance to green`

---

### Task 6: Сквозная проверка, доки, приёмка

- [ ] **Step 1: Полный прогон** — `./ios/scripts/test.sh` (iOS + watch), `./ios/scripts/build.sh`.
- [ ] **Step 2: Парный смоук на симуляторах** — запустить iPhone-симулятор и связанные с ним часы (`xcrun simctl pair`), создать раунд на телефоне, убедиться, что часы получили снапшот; записать удар на часах, убедиться, что он появился на телефоне и в базе.
- [ ] **Step 3: Доки** — `CLAUDE.md`: watch-таргет, отсутствие Firebase на часах и почему, контракт сообщений, очередь и правила синхронизации; `SETUP.md`: как собрать и поставить на часы.
- [ ] **Step 4: Commit + push** — `docs: phase 3c — apple watch notes`.
- [ ] **Step 5 (контроллер):** установка на реальные часы пользователя (нужны сопряжённые с его iPhone часы и доверие профилю разработчика на них); приёмка на поле: раунд с телефона в сумке, запись ударов с запястья, дистанция до грина, проверка синхронизации.

## Риски и ограничения (осознанные)

- **Нет автономности:** без телефона поблизости удары копятся, но не уходят на сервер. Для GPS-часов владельца это не ограничение — на поле у них всё равно нет интернета.
- **Первая сборка watch-таргета** — главный технический риск (встраивание/подпись под Xcode 26). Task 1 намеренно сделан минимальным, чтобы риск вскрылся сразу.
- **Шрифт Playfair Display** на часах может потребовать отдельного включения ресурса; фолбэк — системный шрифт (задокументировать).
- **Батарея:** непрерывный GPS на часах ощутимо расходует заряд; трекинг включается только на экране лунки и останавливается при уходе с него.
