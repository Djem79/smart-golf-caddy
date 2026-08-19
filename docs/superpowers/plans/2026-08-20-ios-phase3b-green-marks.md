# iOS Phase 3b — Green Marks & Distance-to-Green Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Приложение показывает «до грина N м» — фича №1 категории, которой у нас нет. Игрок один раз отмечает грин кнопкой «Я на грине»; со следующего раунда на том же поле дистанция считается автоматически. Метки краудсорсятся: каждый пишет только свои, приложение усредняет по всем игрокам.

**Architecture:** Новая коллекция `courses/{courseKey}/greenMarks/{uid}` — документ на пользователя со всеми его метками поля (`holes: { "1": {lat, lng}, ... }`). Правила: читают все аутентифицированные, пишет только владелец документа — одна ошибочная метка не портит данные остальных, а усреднение по нескольким игрокам повышает точность. Клиент подписывается на метки поля при входе в раунд, усредняет по лунке и считает дистанцию от текущей позиции (GPS-трекинг на экране лунки уже работает с Фазы 2в).

**Ключ поля (`courseKey`)** — стабильный идентификатор: `placeId` для полей из поиска; для введённых вручную (`courseId` вида `custom-<UUID>`, уникальный на раунд) — `name:<нормализованное имя>`, иначе метки никогда не переиспользуются.

**Tech Stack:** Firestore (новая коллекция + правила + тесты в эмуляторе), CoreLocation (уже подключён), SwiftUI.

**Spec:** `docs/superpowers/specs/2026-08-17-ios-app-design.md` — в спеке GPS-до-грина числился отложенным «нет координат гринов»; эта фаза закрывает пробел краудсорсом. Анализ рынка: `.superpowers/sdd/2026-08-18-ios-phase2c-gps-rangefinder/research-market.md`.

## Global Constraints

- Сборка/тесты ТОЛЬКО `./ios/scripts/test.sh` / `./ios/scripts/build.sh`; тест-таргет без Firebase/CoreLocation.
- Правила тестируются `npm run test:rules` (нужен JDK 21+: `export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"`); правила деплоит контроллер.
- `import Firebase*` — только Services/; `import CoreLocation` — только GeolocationService/ShotRangefinder.
- **Приватность:** на сервер уходят координаты ГРИНОВ (статичные точки поля), НЕ траектория игрока. Отметка — явное действие пользователя. Это отражается в usage-description (Фаза 3d) и в доках.
- Гейты качества замера те же, что у дальномера: точность фикса ≤25 м, возраст ≤90 с; иначе кнопка отметки недоступна и дистанция не показывается.
- Русский UI дословно; SF Symbols; ≥48pt; фиксированные шрифты.
- Коммит после каждой задачи.

---

### Task 1: Модель меток, ключ поля, правила Firestore (TDD)

**Files:**
- Create: `ios/SmartGolfCaddy/Models/GreenMarks.swift`
- Modify: `firestore.rules` (коллекция courses)
- Modify: `firestore.rules.test.mjs` (+3 теста)
- Test: `ios/SmartGolfCaddyTests/GreenMarksTests.swift`

**Interfaces:**
- Produces:
  - `struct GreenMark: Equatable { let lat: Double; let lng: Double }`
  - `struct GreenMarkSet: Equatable { var holes: [Int: GreenMark] }` + `init?(data:)` + `firestoreData`
  - `enum Greens { static func courseKey(courseId: String, courseName: String) -> String; static func average(_ sets: [GreenMarkSet], hole: Int) -> GreenMark?; static func distanceMeters(from: GeoFix, to: GreenMark) -> Int }`
  - Правила: `courses/{courseKey}/greenMarks/{uid}` — read: любой аутентифицированный; create/update: только `uid == request.auth.uid` и валидная форма; delete: только владелец

- [ ] **Step 1: Падающие тесты (Swift)**

```swift
// ios/SmartGolfCaddyTests/GreenMarksTests.swift
import XCTest
@testable import SmartGolfCaddy

final class GreenMarksTests: XCTestCase {

    func testCourseKeyUsesPlaceIdWhenAvailable() {
        XCTAssertEqual(Greens.courseKey(courseId: "ChIJp1HB", courseName: "Krylatskoye"), "ChIJp1HB")
    }

    func testCourseKeyFallsBackToNormalizedNameForManualCourses() {
        // Ручной ввод даёт уникальный на раунд id — метки бы не переиспользовались.
        let a = Greens.courseKey(courseId: "custom-ABC123", courseName: "  Dubai   Hills  ")
        let b = Greens.courseKey(courseId: "custom-XYZ789", courseName: "dubai hills")
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.hasPrefix("name:"))
    }

    func testAverageOfMarks() {
        let sets = [
            GreenMarkSet(holes: [1: GreenMark(lat: 55.700, lng: 37.400)]),
            GreenMarkSet(holes: [1: GreenMark(lat: 55.702, lng: 37.402)]),
            GreenMarkSet(holes: [2: GreenMark(lat: 55.710, lng: 37.410)]),
        ]
        let averaged = Greens.average(sets, hole: 1)
        XCTAssertEqual(averaged?.lat ?? 0, 55.701, accuracy: 0.0001)
        XCTAssertEqual(averaged?.lng ?? 0, 37.401, accuracy: 0.0001)
        XCTAssertNil(Greens.average(sets, hole: 3))
    }

    func testDistanceMeters() {
        let fix = GeoFix(lat: 55.700000, lng: 37.400000, accuracy: 5, timestamp: Date())
        let green = GreenMark(lat: 55.701000, lng: 37.400000)   // ~111 м на север
        XCTAssertEqual(Double(Greens.distanceMeters(from: fix, to: green)), 111, accuracy: 3)
    }

    func testFirestoreRoundTrip() {
        let set = GreenMarkSet(holes: [1: GreenMark(lat: 55.7, lng: 37.4),
                                       9: GreenMark(lat: 55.8, lng: 37.5)])
        let restored = GreenMarkSet(data: set.firestoreData)
        XCTAssertEqual(restored, set)
    }
}
```

- [ ] **Step 2: RED.**

- [ ] **Step 3: Реализация модели**

```swift
// ios/SmartGolfCaddy/Models/GreenMarks.swift
// Краудсорс-метки гринов: каждый игрок хранит СВОИ координаты гринов поля,
// приложение усредняет метки всех игроков. Так одна ошибочная отметка не
// портит поле остальным, а несколько отметок повышают точность.
import Foundation

struct GreenMark: Equatable {
    let lat: Double
    let lng: Double
}

struct GreenMarkSet: Equatable {
    var holes: [Int: GreenMark]

    init(holes: [Int: GreenMark]) {
        self.holes = holes
    }

    init?(data: [String: Any]) {
        guard let raw = data["holes"] as? [String: [String: Any]] else { return nil }
        var parsed: [Int: GreenMark] = [:]
        for (key, value) in raw {
            guard let hole = Int(key),
                  let lat = (value["lat"] as? NSNumber)?.doubleValue,
                  let lng = (value["lng"] as? NSNumber)?.doubleValue else { continue }
            parsed[hole] = GreenMark(lat: lat, lng: lng)
        }
        holes = parsed
    }

    var firestoreData: [String: Any] {
        var mapped: [String: [String: Any]] = [:]
        for (hole, mark) in holes {
            mapped[String(hole)] = ["lat": mark.lat, "lng": mark.lng]
        }
        return ["holes": mapped]
    }
}

enum Greens {
    /// Стабильный ключ поля. Для полей из поиска — placeId. Для введённых
    /// вручную id уникален на раунд (`custom-<UUID>`), поэтому ключом служит
    /// нормализованное название — иначе метки никогда бы не переиспользовались.
    static func courseKey(courseId: String, courseName: String) -> String {
        if !courseId.hasPrefix("custom-"), !courseId.isEmpty { return courseId }
        let normalized = courseName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return "name:\(normalized)"
    }

    /// Среднее координат по всем игрокам, отметившим эту лунку.
    static func average(_ sets: [GreenMarkSet], hole: Int) -> GreenMark? {
        let marks = sets.compactMap { $0.holes[hole] }
        guard !marks.isEmpty else { return nil }
        let lat = marks.reduce(0.0) { $0 + $1.lat } / Double(marks.count)
        let lng = marks.reduce(0.0) { $0 + $1.lng } / Double(marks.count)
        return GreenMark(lat: lat, lng: lng)
    }

    static func distanceMeters(from fix: GeoFix, to green: GreenMark) -> Int {
        Int(CoursesService.haversineMetres(fix.lat, fix.lng, green.lat, green.lng).rounded())
    }
}
```

- [ ] **Step 4: Правила Firestore**

В `firestore.rules`, внутри `match /databases/{database}/documents {`, добавить блок (после `users`, до `rounds` — порядок не важен, важна изоляция):

```
    // Краудсорс-координаты гринов. Документ на пользователя: каждый пишет
    // ТОЛЬКО свои метки, читают все аутентифицированные (клиент усредняет).
    // Так одна порченая отметка не ломает поле остальным.
    match /courses/{courseKey}/greenMarks/{userId} {
      allow read: if request.auth != null;
      allow create, update: if request.auth != null
        && request.auth.uid == userId
        && request.resource.data.keys().hasOnly(['holes', 'updatedAt'])
        && request.resource.data.holes is map
        && request.resource.data.holes.size() <= 18;
      allow delete: if request.auth != null && request.auth.uid == userId;
    }
```

В `firestore.rules.test.mjs` добавить три теста в стиле существующих:
- владелец пишет свои метки → успех;
- другой пользователь пишет в чужой документ меток → отказ;
- аутентифицированный читает чужие метки → успех (это by design для усреднения).

- [ ] **Step 5: GREEN** — `./ios/scripts/test.sh`; `export PATH="/opt/homebrew/opt/openjdk/bin:$PATH" && npm run test:rules` (все зелёные, включая новые).

- [ ] **Step 6: Commit** — `feat: green marks model and crowdsourced rules (iOS + firestore)`

---

### Task 2: Сервис меток и вью-модель дистанции (TDD)

**Files:**
- Create: `ios/SmartGolfCaddy/Services/GreensService.swift`
- Modify: `ios/SmartGolfCaddy/ViewModels/HoleTrackerViewModel.swift`
- Test: `ios/SmartGolfCaddyTests/HoleTrackerViewModelTests.swift` (+3)

**Interfaces:**
- Produces:
  - `GreensService.subscribeToMarks(courseKey:onChange:onError:) -> () -> Void` — все документы меток поля → `[GreenMarkSet]`
  - `GreensService.saveMark(courseKey:userId:hole:lat:lng:) async throws` — merge-запись своей метки (`holes.<N>`), не затирая остальные лунки
  - В `HoleTrackerViewModel`: `var greenDistanceMeters: Int?` (nil = нет метки или нет годного фикса), `var canMarkGreen: Bool` (есть годный фикс), `func markGreen() async -> Bool`, `startGreens(courseKey:)` внутри `start()`

- [ ] **Step 1: Падающие тесты** (VM с инжектируемыми зависимостями)

```swift
    @MainActor
    func testGreenDistanceNilWithoutMarks() {
        let model = HoleTrackerViewModel(roundId: "r", holeIndex: 0, userId: "u")
        model.applyGreenMarks([], fix: GeoFix(lat: 55.7, lng: 37.4, accuracy: 5, timestamp: Date()))
        XCTAssertNil(model.greenDistanceMeters)
    }

    @MainActor
    func testGreenDistanceComputedFromAveragedMarks() {
        let model = HoleTrackerViewModel(roundId: "r", holeIndex: 0, userId: "u")  // лунка 1
        let sets = [GreenMarkSet(holes: [1: GreenMark(lat: 55.701, lng: 37.400)])]
        model.applyGreenMarks(sets, fix: GeoFix(lat: 55.700, lng: 37.400, accuracy: 5, timestamp: Date()))
        XCTAssertEqual(Double(model.greenDistanceMeters ?? 0), 111, accuracy: 3)
    }

    @MainActor
    func testStaleFixHidesGreenDistance() {
        let model = HoleTrackerViewModel(roundId: "r", holeIndex: 0, userId: "u")
        let old = GeoFix(lat: 55.700, lng: 37.400, accuracy: 5,
                         timestamp: Date().addingTimeInterval(-300))
        model.applyGreenMarks([GreenMarkSet(holes: [1: GreenMark(lat: 55.701, lng: 37.4)])], fix: old)
        XCTAssertNil(model.greenDistanceMeters)
    }
```

- [ ] **Step 2: RED.**

- [ ] **Step 3: Реализация**

```swift
// ios/SmartGolfCaddy/Services/GreensService.swift
// Чтение/запись краудсорс-меток гринов. Пишем ТОЛЬКО свой документ
// (правила запрещают чужие), читаем все — усреднение на клиенте.
import FirebaseFirestore

enum GreensService {
    static func subscribeToMarks(
        courseKey: String,
        onChange: @escaping ([GreenMarkSet]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> () -> Void {
        let listener = FirebaseService.db
            .collection("courses").document(courseKey)
            .collection("greenMarks")
            .addSnapshotListener { snapshot, error in
                if let error { onError(error); return }
                let sets = (snapshot?.documents ?? []).compactMap { GreenMarkSet(data: $0.data()) }
                onChange(sets)
            }
        return { listener.remove() }
    }

    /// Merge по конкретной лунке: точечный путь `holes.<N>` не трогает
    /// остальные лунки в документе игрока.
    static func saveMark(courseKey: String, userId: String, hole: Int, lat: Double, lng: Double) async throws {
        try await FirebaseService.db
            .collection("courses").document(courseKey)
            .collection("greenMarks").document(userId)
            .setData([
                "holes": [String(hole): ["lat": lat, "lng": lng]],
                "updatedAt": FieldValue.serverTimestamp(),
            ], merge: true)
    }
}
```

`HoleTrackerViewModel`:
- поля `private var greenMarks: [GreenMarkSet] = []`, `private(set) var greenDistanceMeters: Int?`, `var canMarkGreen: Bool { ShotRangefinder.isUsable(GeolocationService.shared.lastFix) }`, `private var courseKey: String?`, `private var unsubscribeGreens: (() -> Void)?`
- `func applyGreenMarks(_ sets: [GreenMarkSet], fix: GeoFix?)` — чистая (тестируемая): если фикс годен (`ShotRangefinder.isUsable`) и есть среднее по `holeIndex + 1` → `greenDistanceMeters = Greens.distanceMeters(...)`, иначе nil; сохраняет `greenMarks = sets`
- в `start()` — если у раунда известны `courseId/courseName`, подписаться: `unsubscribeGreens = GreensService.subscribeToMarks(courseKey:...) { self.applyGreenMarks($0, fix: GeolocationService.shared.lastFix) }`; ключ считается при первом снапшоте раунда (courseId/courseName приходят из `Round`)
- пересчёт при движении: в существующем месте, где обновляется GPS-состояние (например, при каждом `refreshQueueBadge`/таймере), вызывать `applyGreenMarks(greenMarks, fix: GeolocationService.shared.lastFix)`; если такого места нет — добавить `Timer.publish`-независимый лёгкий пересчёт при каждом `save()` и при появлении снапшота раунда (достаточно для MVP; непрерывное обновление раз в секунду — в беклог)
- `func markGreen() async -> Bool` — берёт `GeolocationService.shared.lastFix`, проверяет `isUsable`, зовёт `GreensService.saveMark(courseKey:userId:hole: holeIndex + 1, ...)`; при ошибке ставит `saveError = "Не удалось сохранить метку грина."`
- в `deinit` — `unsubscribeGreens?()`

- [ ] **Step 4: GREEN + build.**

- [ ] **Step 5: Commit** — `feat(ios): greens service and distance-to-green in tracker view-model`

---

### Task 3: Интерфейс — «До грина» и кнопка отметки

**Files:**
- Modify: `ios/SmartGolfCaddy/Views/HoleTrackerView.swift`

**Interfaces:**
- Produces: строка «До грина: N м» (или ярды по настройке профиля) в шапке лунки; кнопка «Я на грине» (SF Symbol `flag.checkered`), доступна при `canMarkGreen`; подсказка «Отметьте грин, когда дойдёте — со следующего раунда покажем дистанцию», когда метки нет.

- [ ] **Step 1: Реализация**

В шапке лунки (рядом с «Пар»/«Дист.»), ниже — компактная строка состояния:

```swift
    @ViewBuilder
    private var greenRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 14))
                .foregroundStyle(DSColor.onPrimary.opacity(0.8))
            if let meters = model.greenDistanceMeters {
                Text(session.profile?.units == .yd
                     ? "До грина: \(Score.metersToYards(meters)) я"
                     : "До грина: \(meters) м")
                    .font(DSFont.labelLG)
                    .foregroundStyle(DSColor.onPrimary)
                    .monospacedDigit()
            } else {
                Text("Грин не отмечен")
                    .font(DSFont.labelMD)
                    .foregroundStyle(DSColor.onPrimary.opacity(0.7))
            }
            Spacer()
            Button {
                Task { _ = await model.markGreen() }
            } label: {
                Text("Я НА ГРИНЕ")
                    .font(DSFont.labelMD)
                    .tracking(1.2)
                    .padding(.horizontal, 12)
                    .frame(minHeight: DS.touchTarget)
            }
            .foregroundStyle(DSColor.onPrimary)
            .background(DSColor.onPrimary.opacity(model.canMarkGreen ? 0.18 : 0.08))
            .clipShape(Capsule())
            .disabled(!model.canMarkGreen)
            .accessibilityLabel("Отметить грин текущей лунки")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .background(DSColor.primaryContainer)
    }
```

Подсказку показывать под счётчиком, когда `model.greenDistanceMeters == nil && model.canMarkGreen`:

```swift
                    Text("Отметьте грин, когда дойдёте — со следующего раунда покажем дистанцию")
                        .font(DSFont.labelMD)
                        .foregroundStyle(DSColor.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.screenPadding)
```

- [ ] **Step 2: Сборка + тесты + скриншот трекера** (без GPS в симуляторе будет «Грин не отмечен» и неактивная кнопка — это валидный рендер; при включённой симуляции локации в Simulator → Features → Location → Custom можно увидеть активную кнопку).

- [ ] **Step 3: Commit** — `feat(ios): distance-to-green row and mark-green button`

---

### Task 4: Деплой правил, смоук, документация

- [ ] **Step 1: Полный прогон** — `./ios/scripts/test.sh`, `./ios/scripts/build.sh`, `npm run test:rules`.
- [ ] **Step 2 (контроллер): деплой правил** — `firebase deploy --only firestore:rules --project smart-golf-caddy`.
- [ ] **Step 3: Смоук с симуляцией локации:** Simulator → Features → Location → Custom Location (широта/долгота поля) → открыть раунд → «Я на грине» → сменить координату на ~150 м → убедиться, что показывается «До грина ~150 м».
- [ ] **Step 4: Доки** — `CLAUDE.md`: коллекция `courses/{courseKey}/greenMarks/{uid}`, правило владельца, усреднение на клиенте, `Greens.courseKey` (placeId либо `name:<норм. имя>`), гейты точности/возраста фикса.
- [ ] **Step 5: Commit + push** — `docs: phase 3b — green marks notes`.
- [ ] **Step 6 (контроллер):** установка на iPhone; приёмка на поле: отметить грины нескольких лунок, в следующем раунде на том же поле увидеть дистанции.
