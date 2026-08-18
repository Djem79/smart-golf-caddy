# iOS Phase 2c — GPS Shot Rangefinder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Приложение автоматически измеряет дистанцию каждого удара по GPS и сохраняет её в раунд. Игрок не делает лишних тапов: позиция запоминается в момент записи удара, дистанция предыдущего удара вычисляется при записи следующего.

**Architecture:** `GeolocationService` расширяется непрерывным трекингом (только пока открыт трекер лунки). Новый `ShotRangefinder` хранит позицию последнего удара на слот (`round:hole:uid`) в файле Application Support, валидирует точность и вычисляет дистанцию (haversine). `HoleTrackerViewModel` при каждой записи удара пересчитывает массив `distances` и отдаёт его в `ShotQueue` → `recordShot`. Сервер сохраняет `distances` рядом с `clubs`, поддерживая инвариант равной длины.

**Tech Stack:** CoreLocation (continuous updates, kCLLocationAccuracyNearestTenMeters), Firestore, Zod (серверные контракты).

**Spec:** `docs/superpowers/specs/2026-08-17-ios-app-design.md` (секция «Нативные фичи v1», п.1 GPS-дальномер удара). Решения пользователя (2026-08-18): дистанции **сохраняются в раунд**; сценарий — **замер прошедшего удара**; способ — **автоматический** (позиция запоминается при записи удара, без дополнительных кнопок).

## Global Constraints

- iOS сборка/тесты ТОЛЬКО `./ios/scripts/test.sh` / `./ios/scripts/build.sh`. Тест-таргет без Firebase/CoreLocation-импортов.
- `import CoreLocation` — только `Services/GeolocationService.swift` и `Services/ShotRangefinder.swift`; `import Firebase*` — только Services/ (+AppDelegate, DEBUG DiagnosticsView).
- Веб-правки минимальны; после них `npm run test:run` и `npx tsc --noEmit`; в `functions/` — `npx tsc --noEmit`.
- **Инвариант данных:** `distances.count == clubs.count` всегда. Значение — метры (Int ≥ 0), где **0 = «дистанция неизвестна»** (последний удар лунки, слабый GPS, удар записан не у мяча). Диапазон валидных значений 3…600 м; всё вне — 0.
- SYNC-контракты (три файла) обновляются вместе: `functions/src/contracts.ts` ↔ `src/types/callable.ts` ↔ `ios/SmartGolfCaddy/Services/CallableContracts.swift`.
- Русский UI дословно; SF Symbols; ≥48pt; фиксированные шрифты; `.preferredColorScheme(.light)` уже стоит.
- **Порядок деплоя не критичен** (серверная Zod-схема не `.strict()` — лишние поля отбрасываются), но functions деплоятся в Task 5 до приёмки.
- Коммит после каждой задачи.
- Интерфейсы фаз 1–2б доступны: `Round/HoleShots/HoleConfig`, `Clubs`, `Scoring`, `Score`, `RoundsService`, `ShotQueue`, `AppRouter/AppStore`, `SessionViewModel`, `DSButton`, DS-токены, `CoursesService.haversineMetres`, `GeolocationService`.

---

### Task 1: Контракты и модели end-to-end (сервер + веб + iOS)

**Files:**
- Modify: `functions/src/contracts.ts` (RecordShotInput + distances)
- Modify: `functions/src/index.ts` (recordShot пишет distances, держит инвариант длины)
- Modify: `src/types/callable.ts` (зеркало)
- Modify: `src/types/index.ts` (HoleShots.distances + хелпер getHoleDistances)
- Modify: `ios/SmartGolfCaddy/Services/CallableContracts.swift` (зеркало)
- Modify: `ios/SmartGolfCaddy/Models/Round.swift` (HoleShots.distances + resolvedDistances + firestoreData)
- Test: `ios/SmartGolfCaddyTests/ModelsTests.swift` (+3), `src/services/scoring.test.ts` (не трогаем) / `src/types/index.test.ts` — если файла нет, тест хелпера положить в `src/services/scoring.test.ts` рядом с прочими

**Interfaces:**
- Produces (T2–T4 зовут дословно):
  - Swift: `HoleShots.distances: [Int]`, `HoleShots.resolvedDistances: [Int]` (выровнен по длине `resolvedClubs`: недостающие — 0, лишние отброшены), `RecordShotInput.distances: [Int]?`
  - TS: `HoleShots.distances?: number[]`, `getHoleDistances(shots): number[]` (та же семантика выравнивания), `RecordShotInput.distances?: number[]`
  - Сервер: `distances` сохраняется; если поле не пришло — существующие дистанции сохраняются и подгоняются под новую длину `clubs`

- [ ] **Step 1: Падающие тесты (Swift)**

В `ModelsTests.swift` добавить:

```swift
    func testResolvedDistancesPadsToClubsLength() {
        let shots = HoleShots(count: 3, clubs: ["Driver", "7i", "Putter"],
                              distances: [215], legacyClub: nil, updatedAt: nil)
        XCTAssertEqual(shots.resolvedDistances, [215, 0, 0])
    }

    func testResolvedDistancesTrimsExtra() {
        let shots = HoleShots(count: 1, clubs: ["Driver"],
                              distances: [215, 140], legacyClub: nil, updatedAt: nil)
        XCTAssertEqual(shots.resolvedDistances, [215])
    }

    func testDistancesRoundTripThroughFirestoreData() {
        let shots = HoleShots(count: 2, clubs: ["Driver", "PW"],
                              distances: [215, 0], legacyClub: nil, updatedAt: nil)
        let restored = HoleShots(data: shots.firestoreData)
        XCTAssertEqual(restored?.distances, [215, 0])
        XCTAssertEqual(restored?.resolvedDistances, [215, 0])
    }
```

Примечание исполнителю: существующий инициализатор `HoleShots(count:clubs:legacyClub:updatedAt:)` получает новый параметр `distances:` — обнови ВСЕ существующие вызовы в тестах и коде (grep `HoleShots(count:`), передавая `distances: []`, иначе сборка тестов упадёт.

- [ ] **Step 2: RED** — `./ios/scripts/test.sh` падает компиляцией.

- [ ] **Step 3: Реализация**

`ios/SmartGolfCaddy/Models/Round.swift`, в `HoleShots`:

```swift
    var distances: [Int]   // метры; 0 = неизвестно. Длина выравнивается по clubs.
```

в memberwise-init добавить параметр `distances: [Int]` (после clubs), в `init?(data:)`:

```swift
        distances = (data["distances"] as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue } ?? []
```

в `firestoreData` добавить `"distances": distances`, и новое свойство:

```swift
    /// Дистанции, выровненные по длине серии: недостающие — 0, лишние отброшены.
    /// Инвариант хранения (distances.count == clubs.count) может нарушиться
    /// у документов, записанных старыми клиентами — здесь он восстанавливается.
    var resolvedDistances: [Int] {
        let target = resolvedClubs.count
        if distances.count == target { return distances }
        if distances.count > target { return Array(distances.prefix(target)) }
        return distances + Array(repeating: 0, count: target - distances.count)
    }
```

`ios/SmartGolfCaddy/Services/CallableContracts.swift`, в `RecordShotInput` добавить поле `let distances: [Int]?` (после clubs).

`functions/src/contracts.ts`:

```ts
export const RecordShotInput = z
  .object({
    roundId: z.string().min(1).max(128),
    holeIndex: z.number().int().min(0).max(17),
    clubs: z.array(z.string().min(1).max(50)).max(30),
    // Дистанции ударов в метрах, параллельно clubs. 0 = неизвестна
    // (последний удар лунки, слабый GPS). Необязательно: веб-клиент
    // дистанции не измеряет и поле не шлёт.
    distances: z.array(z.number().int().min(0).max(1000)).max(30).optional(),
    targetUid: z.string().min(1).max(128).optional(),
  })
  .refine(v => v.distances == null || v.distances.length === v.clubs.length, {
    message: 'Длина distances должна совпадать с clubs',
  })
```

`functions/src/index.ts`, в recordShot: деструктуризацию дополнить `distances`, и запись слота заменить на:

```ts
      // Дистанции: пришли — пишем как есть (клиент шлёт полный массив);
      // не пришли (веб) — сохраняем прежние, подгоняя под новую длину clubs,
      // чтобы редактирование с веба не стирало замеры, сделанные на iOS.
      const prevDistances = Array.isArray(
        (h => (h?.shots as Record<string, { distances?: unknown }> | undefined)?.[target]?.distances)(
          data.holes[holeIndex],
        ),
      )
        ? ((data.holes[holeIndex].shots as Record<string, { distances?: number[] }>)[target]
            .distances as number[])
        : []
      const nextDistances =
        distances ??
        Array.from({ length: clubs.length }, (_, i) => prevDistances[i] ?? 0)
```

и в объекте слота добавить `distances: nextDistances,` после `clubs,`.

Примечание исполнителю: выражение выше нарочно многословно, чтобы обойти типизацию `shots: Record<string, unknown>`; допустимо переписать чище (например, вынести `const prevSlot = (data.holes[holeIndex]?.shots ?? {})[target] as { distances?: number[] } | undefined`) — важно поведение, а не форма.

`src/types/callable.ts` — в `RecordShotInput` добавить `distances?: number[]` с комментарием «метры; 0 = неизвестна».

`src/types/index.ts` — в `HoleShots` добавить `distances?: number[]` и хелпер рядом с `getHoleClubs`:

```ts
// Дистанции ударов, выровненные по длине серии (0 = неизвестна). Веб их не
// измеряет, но отображает то, что записал iOS-клиент.
export function getHoleDistances(shots: HoleShots | undefined): number[] {
  const clubs = getHoleClubs(shots)
  const raw = shots?.distances ?? []
  return clubs.map((_, i) => raw[i] ?? 0)
}
```

- [ ] **Step 4: GREEN** — `./ios/scripts/test.sh`; `npx tsc --noEmit`; `cd functions && npx tsc --noEmit`; `npm run test:run` (веб-тесты не должны сломаться).

- [ ] **Step 5: Commit**

```bash
git add functions/src src/types ios/SmartGolfCaddy ios/SmartGolfCaddyTests
git commit -m "feat: shot distances in round schema — server, contracts, models (iOS+web)"
```

---

### Task 2: Сервис замера (ShotRangefinder, TDD)

**Files:**
- Modify: `ios/SmartGolfCaddy/Services/GeolocationService.swift` (непрерывный трекинг + lastFix)
- Create: `ios/SmartGolfCaddy/Services/ShotRangefinder.swift`
- Test: `ios/SmartGolfCaddyTests/ShotRangefinderTests.swift`

**Interfaces:**
- Produces:
  - `struct GeoFix: Equatable { let lat: Double; let lng: Double; let accuracy: Double }`
  - `GeolocationService.startTracking()` / `.stopTracking()` / `var lastFix: GeoFix?` (обновляется на main)
  - `final class ShotRangefinder` с `static let shared`; `init(storeURL:fixProvider:)` для тестов
  - `func markShot(roundId:holeIndex:targetUid:shotIndex:)` — запомнить текущую позицию как точку удара `shotIndex`
  - `func measure(roundId:holeIndex:targetUid:) -> (previousIndex: Int, meters: Int)?` — дистанция от запомненной точки до текущей позиции; nil, если точки нет / нет фикса / точность плоха
  - `static func isUsable(_ fix: GeoFix?) -> Bool` (accuracy > 0 && ≤ 25)
  - `static func sanitize(_ meters: Double) -> Int` (3…600 → округление, иначе 0)
  - `func clear(roundId:holeIndex:targetUid:)`

- [ ] **Step 1: Падающие тесты**

```swift
// ios/SmartGolfCaddyTests/ShotRangefinderTests.swift
import XCTest
@testable import SmartGolfCaddy

final class ShotRangefinderTests: XCTestCase {
    private var storeURL: URL!

    override func setUp() {
        super.setUp()
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rangefinder-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeURL)
        super.tearDown()
    }

    private func makeRangefinder(fix: @escaping () -> GeoFix?) -> ShotRangefinder {
        ShotRangefinder(storeURL: storeURL, fixProvider: fix)
    }

    func testAccuracyGate() {
        XCTAssertTrue(ShotRangefinder.isUsable(GeoFix(lat: 1, lng: 1, accuracy: 8)))
        XCTAssertFalse(ShotRangefinder.isUsable(GeoFix(lat: 1, lng: 1, accuracy: 60)))
        XCTAssertFalse(ShotRangefinder.isUsable(GeoFix(lat: 1, lng: 1, accuracy: -1)))
        XCTAssertFalse(ShotRangefinder.isUsable(nil))
    }

    func testSanitizeRange() {
        XCTAssertEqual(ShotRangefinder.sanitize(214.6), 215)
        XCTAssertEqual(ShotRangefinder.sanitize(1.2), 0)     // ближе 3 м — шум
        XCTAssertEqual(ShotRangefinder.sanitize(900), 0)     // дальше 600 м — выброс
    }

    func testMeasureBetweenTwoFixes() {
        // ~111 м на север: 0.001° широты
        var current = GeoFix(lat: 55.700000, lng: 37.400000, accuracy: 5)
        let rangefinder = makeRangefinder(fix: { current })
        rangefinder.markShot(roundId: "r", holeIndex: 0, targetUid: "u", shotIndex: 0)
        current = GeoFix(lat: 55.701000, lng: 37.400000, accuracy: 5)
        let result = rangefinder.measure(roundId: "r", holeIndex: 0, targetUid: "u")
        XCTAssertEqual(result?.previousIndex, 0)
        XCTAssertEqual(Double(result?.meters ?? 0), 111, accuracy: 3)
    }

    func testMeasureWithoutMarkReturnsNil() {
        let rangefinder = makeRangefinder(fix: { GeoFix(lat: 1, lng: 1, accuracy: 5) })
        XCTAssertNil(rangefinder.measure(roundId: "r", holeIndex: 0, targetUid: "u"))
    }

    func testMeasureWithBadAccuracyReturnsNil() {
        var current = GeoFix(lat: 55.7, lng: 37.4, accuracy: 5)
        let rangefinder = makeRangefinder(fix: { current })
        rangefinder.markShot(roundId: "r", holeIndex: 0, targetUid: "u", shotIndex: 0)
        current = GeoFix(lat: 55.701, lng: 37.4, accuracy: 80)
        XCTAssertNil(rangefinder.measure(roundId: "r", holeIndex: 0, targetUid: "u"))
    }

    func testMarksAreSlotScopedAndSurviveReload() {
        let rangefinder = makeRangefinder(fix: { GeoFix(lat: 55.7, lng: 37.4, accuracy: 5) })
        rangefinder.markShot(roundId: "r", holeIndex: 0, targetUid: "u", shotIndex: 2)
        // Другой слот — своя точка
        XCTAssertNil(rangefinder.measure(roundId: "r", holeIndex: 1, targetUid: "u"))
        // «Перезапуск» — точка на месте
        let reloaded = makeRangefinder(fix: { GeoFix(lat: 55.701, lng: 37.4, accuracy: 5) })
        XCTAssertEqual(reloaded.measure(roundId: "r", holeIndex: 0, targetUid: "u")?.previousIndex, 2)
    }

    func testClearRemovesMark() {
        let rangefinder = makeRangefinder(fix: { GeoFix(lat: 55.7, lng: 37.4, accuracy: 5) })
        rangefinder.markShot(roundId: "r", holeIndex: 0, targetUid: "u", shotIndex: 0)
        rangefinder.clear(roundId: "r", holeIndex: 0, targetUid: "u")
        XCTAssertNil(rangefinder.measure(roundId: "r", holeIndex: 0, targetUid: "u"))
    }
}
```

- [ ] **Step 2: RED.**

- [ ] **Step 3: Реализация**

`GeolocationService.swift` — добавить (не ломая существующий `request`):

```swift
struct GeoFix: Equatable {
    let lat: Double
    let lng: Double
    let accuracy: Double   // метры; < 0 = недостоверно
}
```

в классе:

```swift
    /// Последний известный фикс — читается дальномером в момент записи удара.
    private(set) var lastFix: GeoFix?
    private var tracking = false

    /// Непрерывный трекинг на время экрана лунки. Точность «до 10 метров»
    /// достаточна для замера ударов и экономнее полной.
    func startTracking() {
        guard !tracking else { return }
        tracking = true
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        guard tracking else { return }
        tracking = false
        manager.stopUpdatingLocation()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
```

в `didUpdateLocations` — перед существующим `onUpdate`-колбэком запомнить фикс:

```swift
        let fix = GeoFix(lat: location.coordinate.latitude,
                         lng: location.coordinate.longitude,
                         accuracy: location.horizontalAccuracy)
        DispatchQueue.main.async { [weak self] in
            self?.lastFix = fix
        }
```

и в `locationManagerDidChangeAuthorization` при авторизации — если `tracking`, звать `manager.startUpdatingLocation()` вместо `requestLocation()`.

```swift
// ios/SmartGolfCaddy/Services/ShotRangefinder.swift
// Автоматический замер дистанции удара: позиция запоминается в момент
// записи удара, дистанция считается при записи следующего. Точка живёт в
// файле (переживает перезапуск), привязана к слоту round:hole:uid.
import Foundation

final class ShotRangefinder: @unchecked Sendable {

    static let shared = ShotRangefinder(
        storeURL: ShotRangefinder.defaultStoreURL(),
        fixProvider: { GeolocationService.shared.lastFix }
    )

    /// Худшая точность фикса, при которой замер считается достоверным.
    static let accuracyLimitMeters = 25.0
    /// Разумные границы длины удара — вне их значение считаем неизвестным.
    static let minMeters = 3.0
    static let maxMeters = 600.0

    private struct Mark: Codable {
        var lat: Double
        var lng: Double
        var shotIndex: Int
    }

    private let storeURL: URL
    private let fixProvider: () -> GeoFix?
    private let ioQueue = DispatchQueue(label: "sgc.rangefinder.io")

    init(storeURL: URL, fixProvider: @escaping () -> GeoFix?) {
        self.storeURL = storeURL
        self.fixProvider = fixProvider
    }

    static func isUsable(_ fix: GeoFix?) -> Bool {
        guard let fix else { return false }
        return fix.accuracy > 0 && fix.accuracy <= accuracyLimitMeters
    }

    static func sanitize(_ meters: Double) -> Int {
        guard meters >= minMeters, meters <= maxMeters else { return 0 }
        return Int(meters.rounded())
    }

    func markShot(roundId: String, holeIndex: Int, targetUid: String, shotIndex: Int) {
        guard let fix = fixProvider(), Self.isUsable(fix) else { return }
        mutate { $0[Self.key(roundId, holeIndex, targetUid)] = Mark(lat: fix.lat, lng: fix.lng, shotIndex: shotIndex) }
    }

    func measure(roundId: String, holeIndex: Int, targetUid: String) -> (previousIndex: Int, meters: Int)? {
        guard let fix = fixProvider(), Self.isUsable(fix) else { return nil }
        guard let mark = load()[Self.key(roundId, holeIndex, targetUid)] else { return nil }
        let meters = CoursesService.haversineMetres(mark.lat, mark.lng, fix.lat, fix.lng)
        return (mark.shotIndex, Self.sanitize(meters))
    }

    func clear(roundId: String, holeIndex: Int, targetUid: String) {
        mutate { $0.removeValue(forKey: Self.key(roundId, holeIndex, targetUid)) }
    }

    // MARK: хранилище

    private static func key(_ roundId: String, _ holeIndex: Int, _ targetUid: String) -> String {
        "\(roundId):\(holeIndex):\(targetUid)"
    }

    private func load() -> [String: Mark] {
        ioQueue.sync {
            guard let data = try? Data(contentsOf: storeURL) else { return [:] }
            return (try? JSONDecoder().decode([String: Mark].self, from: data)) ?? [:]
        }
    }

    private func mutate(_ block: (inout [String: Mark]) -> Void) {
        ioQueue.sync {
            var map: [String: Mark] = {
                guard let data = try? Data(contentsOf: storeURL) else { return [:] }
                return (try? JSONDecoder().decode([String: Mark].self, from: data)) ?? [:]
            }()
            block(&map)
            if let data = try? JSONEncoder().encode(map) {
                try? data.write(to: storeURL, options: .atomic)
            }
        }
    }

    private static func defaultStoreURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("shot-marks-v1.json")
    }
}
```

- [ ] **Step 4: GREEN + build.**

- [ ] **Step 5: Commit**

```bash
git add ios/SmartGolfCaddy/Services ios/SmartGolfCaddyTests/ShotRangefinderTests.swift
git commit -m "feat(ios): shot rangefinder service — auto-measure between recorded shots"
```

---

### Task 3: Очередь и вью-модель трекера (TDD)

**Files:**
- Modify: `ios/SmartGolfCaddy/Services/ShotQueue.swift` (PendingShot.distances → callable)
- Modify: `ios/SmartGolfCaddy/Services/RoundsService.swift` (recordShot принимает distances)
- Modify: `ios/SmartGolfCaddy/ViewModels/HoleTrackerViewModel.swift` (замер при сохранении)
- Test: `ios/SmartGolfCaddyTests/ShotQueueTests.swift` (обновить фикстуры + 1 тест), `ios/SmartGolfCaddyTests/HoleTrackerViewModelTests.swift` (+2)

**Interfaces:**
- Produces:
  - `RoundsService.recordShot(roundId:holeIndex:targetUid:clubs:distances:)`
  - `PendingShot.distances: [Int]?` (optional — старые файлы очереди без поля декодируются без миграции; использовать как `?? []`); `ShotQueue.recordShotQueued(roundId:holeIndex:targetUid:clubs:distances:) async -> RecordOutcome`
  - `HoleTrackerViewModel`: `var currentDistances: [Int]` (дерив: optimistic → pending → server), `var gpsReady: Bool`, `func save(_ clubs: [String]) async -> Bool` (сигнатура прежняя — дистанции считает сама), `Optimistic.distances`

**Логика замера в save (порт решения пользователя):**
1. Пусть `previous = currentClubs`, `next = clubs` (аргумент save).
2. Если `next.count > previous.count` (добавили удар с индексом `newIndex = next.count - 1`):
   - `measure(...)` → если вернулся `(previousIndex, meters)` и `previousIndex < previous.count` → `distances[previousIndex] = meters` (дистанция удара, который был сделан ДО перехода);
   - затем `markShot(shotIndex: newIndex)` — запомнить позицию нового удара.
3. Если `next.count < previous.count` (убрали удар) — обрезать distances до новой длины; перезапомнить точку для последнего оставшегося удара (`markShot(shotIndex: next.count - 1)`), чтобы следующий замер считался от актуальной позиции.
4. Массив distances всегда выравнивается по длине next (padding нулями).

- [ ] **Step 1: Падающие тесты**

В `HoleTrackerViewModelTests.swift` (VM конструируется напрямую; дальномер и очередь инжектируются — см. реализацию):

```swift
    @MainActor
    func testDistancesDerivedLikeClubs() {
        let model = HoleTrackerViewModel(roundId: "r", holeIndex: 0, userId: "u")
        model.optimistic = .init(slot: "0:u", clubs: ["Driver", "7i"],
                                 distances: [215, 0], awaitingKey: "Driver|7i")
        XCTAssertEqual(model.displayedDistances(serverDistances: [0], pendingDistances: nil,
                                                serverClubs: ["Driver"], pendingClubs: nil), [215, 0])
    }

    @MainActor
    func testDistancesFallBackToServerWhenEchoed() {
        let model = HoleTrackerViewModel(roundId: "r", holeIndex: 0, userId: "u")
        model.optimistic = .init(slot: "0:u", clubs: ["Driver"], distances: [0], awaitingKey: "Driver")
        // сервер отэхоил и знает дистанцию — показываем серверную
        XCTAssertEqual(model.displayedDistances(serverDistances: [215], pendingDistances: nil,
                                                serverClubs: ["Driver"], pendingClubs: nil), [215])
    }
```

В `ShotQueueTests.swift` — обновить существующие вызовы `recordShotQueued(...)` добавив `distances:` (например `distances: []`), и добавить:

```swift
    func testQueuePreservesDistances() async {
        let queue = makeQueue(online: { false })
        _ = await queue.recordShotQueued(roundId: "r", holeIndex: 0, targetUid: "u",
                                         clubs: ["Driver", "7i"], distances: [215, 0])
        XCTAssertEqual(queue.pendingShot(roundId: "r", holeIndex: 0, targetUid: "u")?.distances, [215, 0])
    }
```

- [ ] **Step 2: RED.**

- [ ] **Step 3: Реализация**

`RoundsService.recordShot` — параметр `distances: [Int]` и передача в `RecordShotInput(... distances: distances, targetUid: targetUid)`.

`ShotQueue`:
- `PendingShot` + `var distances: [Int]` (Codable; старые записи в файле без поля → декодер упадёт! Поэтому объявить `var distances: [Int] = []` и реализовать `init(from:)`? Проще: пометить поле как optional в модели хранения — `var distances: [Int]?` c вычисляемым доступом. РЕШЕНИЕ: `var distances: [Int]?` в PendingShot, а на использование — `shot.distances ?? []`. Это переживает старые файлы очереди без миграции.)
- `recordShotQueued(... distances: [Int])` кладёт их в entry и передаёт в sender.
- Дефолтный sender: `RoundsService.recordShot(..., distances: shot.distances ?? [])`.

`HoleTrackerViewModel`:
- `Optimistic` + `var distances: [Int]`.
- `currentDistances` и `displayedDistances(serverDistances:pendingDistances:serverClubs:pendingClubs:)` — зеркалят логику `displayedClubs` (optimistic пока «впереди» сервера → pending → server), длина выравнивается по соответствующей серии клюшек.
- `save(_ clubs:)`: перед вызовом очереди выполнить алгоритм замера (шаги 1–4 выше), собрать `distances`, положить в `optimistic`, передать в `ShotQueue.shared.recordShotQueued(..., distances: distances)`.
- Дальномер инжектируется для тестов: `private let rangefinder: ShotRangefinder` с дефолтом `.shared` в существующем init (добавить параметр со значением по умолчанию, чтобы вызовы во View не менялись).
- `gpsReady`: `ShotRangefinder.isUsable(GeolocationService.shared.lastFix)` — читается вью для индикатора; обновлять в `start()` через таймер не нужно, достаточно вычисляемого свойства (SwiftUI перерисует при изменениях состояния VM; допустимо, что индикатор обновится не мгновенно).
- В `start()` — `GeolocationService.shared.startTracking()`; в `deinit` — `GeolocationService.shared.stopTracking()`.

- [ ] **Step 4: GREEN + build.**

- [ ] **Step 5: Commit**

```bash
git add ios/SmartGolfCaddy ios/SmartGolfCaddyTests
git commit -m "feat(ios): wire distances through queue and tracker view-model"
```

---

### Task 4: Интерфейс — дистанции в трекере и итогах

**Files:**
- Modify: `ios/SmartGolfCaddy/Views/HoleTrackerView.swift` (чипы серии + строка состояния GPS)
- Modify: `ios/SmartGolfCaddy/Views/RoundResultsView.swift` (средняя дистанция по клюшке)
- Modify: `ios/SmartGolfCaddy/Models/Scoring.swift` (+avgDistance в ClubStat)
- Test: `ios/SmartGolfCaddyTests/ScoringTests.swift` (+1)

**Interfaces:**
- Produces: `ClubStat.avgDistanceMeters: Int` (0 = нет замеров; среднее по ненулевым дистанциям этой клюшки).

- [ ] **Step 1: Падающий тест**

```swift
    func testClubUsageAveragesDistances() {
        let round = makeRound(holes: [
            hole(1, par: 4, shots: ["u1": ["count": 3, "clubs": ["Driver", "Driver", "Putter"],
                                           "distances": [200, 220, 0]]]),
        ])
        let usage = Scoring.clubUsage(round: round, userId: "u1")
        let driver = usage.first { $0.club == "Driver" }
        XCTAssertEqual(driver?.avgDistanceMeters, 210)
        XCTAssertEqual(usage.first { $0.club == "Putter" }?.avgDistanceMeters, 0)
    }
```

- [ ] **Step 2: RED.**

- [ ] **Step 3: Реализация**

`Scoring.swift`: в `ClubStat` добавить `let avgDistanceMeters: Int`; в `clubUsage(rounds:userId:)` параллельно счётчику собирать суммы/количества ненулевых дистанций (`hole.shots[userId]?.resolvedDistances`, индекс синхронен с `resolvedClubs`) и считать среднее округлением. Все существующие конструкторы `ClubStat` в тестах/коде обновить.

`HoleTrackerView.swift`:
- В `series` чип показывает дистанцию, когда она известна:

```swift
                Text(model.currentDistances.indices.contains(index) && model.currentDistances[index] > 0
                     ? "\(index + 1). \(Clubs.label(for: club, in: fullBag)) · \(model.currentDistances[index]) м"
                     : "\(index + 1). \(Clubs.label(for: club, in: fullBag))")
```

- Под счётчиком — строка состояния (только когда серия непуста):

```swift
                    Label(model.gpsReady ? "GPS готов — дистанции пишутся" : "Ждём GPS — дистанции не пишутся",
                          systemImage: model.gpsReady ? "location.fill" : "location.slash")
                        .font(DSFont.labelMD)
                        .foregroundStyle(DSColor.onSurfaceVariant)
```

`RoundResultsView.swift`: в секции клюшек чип дополняется средней дистанцией, когда она есть:

```swift
                        Text(stat.avgDistanceMeters > 0
                             ? "\(Clubs.label(for: stat.club, in: viewerBag)) · \(stat.count) (\(stat.percent)%) · ср. \(stat.avgDistanceMeters) м"
                             : "\(Clubs.label(for: stat.club, in: viewerBag)) · \(stat.count) (\(stat.percent)%)")
```

- [ ] **Step 4: GREEN + build + скриншот трекера** (серия с дистанцией не проверяется без GPS — достаточно рендера строки состояния «Ждём GPS…» на симуляторе без локации).

- [ ] **Step 5: Commit**

```bash
git add ios/SmartGolfCaddy ios/SmartGolfCaddyTests
git commit -m "feat(ios): show shot distances in tracker series and club stats"
```

---

### Task 5: Деплой функций, документация, подготовка приёмки

- [ ] **Step 1: Полный прогон** — `./ios/scripts/test.sh`, `./ios/scripts/build.sh`, `npm run test:run`, `npx tsc --noEmit`, `cd functions && npx tsc --noEmit`.
- [ ] **Step 2: Деплой сервера** (контроллер): `source ~/.nvm/nvm.sh && firebase deploy --only functions:recordShot --project smart-golf-caddy`; убедиться, что деплой успешен (иначе дистанции не сохранятся).
- [ ] **Step 3: Правила Firestore** — проверить, что изменений не требуется (`holes` пишет только сервер; клиентские записи заблокированы) — grep по `firestore.rules`, изменений НЕ вносить.
- [ ] **Step 4: Доки** — в `CLAUDE.md` (iOS-проза) 3–4 строки: `Services/ShotRangefinder.swift` (авто-замер: точка запоминается при записи удара, дистанция считается при следующем; слот `round:hole:uid`, файл в Application Support; точность ≤25 м, диапазон 3…600 м, 0 = неизвестно), `HoleShots.distances` (инвариант длины == clubs, сервер поддерживает при веб-редактировании).
- [ ] **Step 5: Commit + push** `docs: phase 2c — GPS rangefinder notes`.
- [ ] **Step 6 (контроллер): сборка и установка** на симулятор и iPhone; приёмка на поле/улице: пройти 100+ метров между записями ударов, проверить, что дистанция появилась в серии и в итогах; проверить офлайн (авиарежим — дистанции должны сохраниться в очереди и уйти позже).
