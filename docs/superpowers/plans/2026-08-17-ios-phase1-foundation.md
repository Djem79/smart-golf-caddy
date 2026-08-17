# iOS Phase 1 — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Нативное SwiftUI-приложение запускается на симуляторе и iPhone, логинится через Google в существующий Firebase-проект `smart-golf-caddy`, создаёт/читает профиль пользователя и успешно вызывает callable через App Check (debug provider).

**Architecture:** Слои зеркалят веб: Views → ViewModels (@Observable) → Services → Firebase iOS SDK; Models — чистые структуры без Firebase-зависимостей. Проект генерируется XcodeGen из `project.yml` (`.xcodeproj` не в git). Firestore Timestamp конвертируется в Date на границе Services.

**Tech Stack:** Swift 5.10+ / SwiftUI, iOS 17+, XcodeGen, SPM: firebase-ios-sdk (FirebaseAuth, FirebaseFirestore, FirebaseFunctions, FirebaseAppCheck) + GoogleSignIn-iOS.

**Spec:** `docs/superpowers/specs/2026-08-17-ios-app-design.md`

## Global Constraints

- **Путь репозитория чистый** (2026-08-17 родительская папка переименована: U+00A0 → обычный пробел; симлинк со старым именем оставлен). Штатные Read/Write/Edit работают.
- **Сборка ТОЛЬКО с DerivedData вне iCloud**: `export DD="$HOME/Library/Developer/Xcode/DerivedData/SmartGolfCaddy-local"`. Артефакты внутри ~/Documents портятся iCloud File Provider (xattr `com.apple.fileprovider.fpfs#P` → codesign «resource fork … detritus not allowed»). Никогда не собирать в `ios/build/`.
- Русский UI во всех user-facing строках. Плюрализация — только через `pluralRu`.
- Никаких эмодзи в UI и коде — только SF Symbols.
- Touch targets ≥ 48 pt (`DS.touchTarget`).
- Deployment target **iOS 17.0** (нужен `@Observable`).
- Bundle ID: `com.dzhambulat.smartgolfcaddy`. Firebase-проект: `smart-golf-caddy`.
- `import Firebase*` / `import GoogleSignIn` разрешены ТОЛЬКО в `ios/SmartGolfCaddy/Services/*.swift` и `App/AppDelegate.swift`.
- `ios/SmartGolfCaddy.xcodeproj` — генерируется (`cd ios && xcodegen`), руками не редактируется, в git не попадает.
- Не коммитить: `GoogleService-Info.plist`, `ios/Config/Local.xcconfig`, `ios/build/`.
- Все xcodebuild-команды выполняются из `ios/`. Перед ними в свежей сессии: `export DD="$HOME/Library/Developer/Xcode/DerivedData/SmartGolfCaddy-local"` и `export SIM_NAME="iPhone 17"` — либо имя из `xcrun simctl list devices available | grep iPhone` (взять первое доступное).
- Cloud Functions регион: `us-central1`.
- Коммиты после каждой задачи (memory: standing OK без вопросов).

---

### Task 1: Окружение Xcode

**Files:** нет изменений в репо (только системная настройка).

**Interfaces:**
- Produces: рабочий тулчейн — `xcodebuild -version` показывает полный Xcode; симулятор iOS доступен; `xcodegen` в PATH.

- [ ] **Step 1: Проверить, что Xcode установлен**

Run: `ls /Applications/ | grep -i "^Xcode"`
Expected: `Xcode.app`. Если пусто — СТОП: попросить пользователя установить Xcode из Mac App Store и дождаться окончания установки.

- [ ] **Step 2: Переключить developer directory (может запросить пароль)**

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcode-select -p
```
Expected: `/Applications/Xcode.app/Contents/Developer`

- [ ] **Step 3: Принять лицензию и запустить first-launch**

```bash
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
xcodebuild -version
```
Expected: `Xcode 16.x` или новее, без ошибок про лицензию.

- [ ] **Step 4: Убедиться, что iOS-платформа скачана**

```bash
xcrun simctl list runtimes | grep iOS || xcodebuild -downloadPlatform iOS
xcrun simctl list devices available | grep iPhone | head -3
```
Expected: минимум один доступный iPhone-симулятор. Записать его имя — оно используется как `$SIM_NAME` во всех задачах.

- [ ] **Step 5: Установить XcodeGen**

```bash
brew install xcodegen
xcodegen --version
```
Expected: `Version: 2.x`

---

### Task 2: Скелет проекта (XcodeGen)

**Files:**
- Create: `ios/project.yml`
- Create: `ios/Config/Local.xcconfig.example`
- Create: `ios/Config/Local.xcconfig` (копия example, не в git)
- Create: `ios/SmartGolfCaddy/App/SmartGolfCaddyApp.swift`
- Create: `ios/SmartGolfCaddy/App/RootView.swift`
- Create: `ios/SmartGolfCaddyTests/SmokeTests.swift`
- Modify: `.gitignore` (в корне репо)

**Interfaces:**
- Produces: собираемый app-таргет `SmartGolfCaddy` + тест-таргет `SmartGolfCaddyTests`; вью `RootView` (Task 6 заменит содержимое); команда сборки/тестов для всех следующих задач.

- [ ] **Step 1: Создать project.yml**

```yaml
# ios/project.yml — единственный источник правды для .xcodeproj.
# После правок: cd ios && xcodegen
name: SmartGolfCaddy
options:
  bundleIdPrefix: com.dzhambulat
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true
configFiles:
  Debug: Config/Local.xcconfig
  Release: Config/Local.xcconfig
targets:
  SmartGolfCaddy:
    type: application
    platform: iOS
    sources: [SmartGolfCaddy]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.dzhambulat.smartgolfcaddy
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: $(DEV_TEAM)
        GENERATE_INFOPLIST_FILE: NO
    info:
      path: SmartGolfCaddy/Info.plist
      properties:
        CFBundleDisplayName: Smart Golf Caddy
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
        UILaunchScreen: {}
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
  SmartGolfCaddyTests:
    type: bundle.unit-test
    platform: iOS
    sources: [SmartGolfCaddyTests]
    dependencies:
      - target: SmartGolfCaddy
schemes:
  SmartGolfCaddy:
    build:
      targets:
        SmartGolfCaddy: all
        SmartGolfCaddyTests: [test]
    test:
      targets: [SmartGolfCaddyTests]
```

- [ ] **Step 2: Создать Local.xcconfig.example и рабочую копию**

```
// ios/Config/Local.xcconfig.example
// Скопировать в Local.xcconfig (gitignored) и заполнить:
//   DEV_TEAM — Team ID личной команды (Xcode → Settings → Accounts), пусто для симулятора
//   GOOGLE_REVERSED_CLIENT_ID — из GoogleService-Info.plist (Task 5)
DEV_TEAM =
GOOGLE_REVERSED_CLIENT_ID = placeholder.invalid
```

Run: `cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig`

- [ ] **Step 3: Создать App entry и RootView**

```swift
// ios/SmartGolfCaddy/App/SmartGolfCaddyApp.swift
import SwiftUI

@main
struct SmartGolfCaddyApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}
```

```swift
// ios/SmartGolfCaddy/App/RootView.swift
import SwiftUI

struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.golf")
                .font(.system(size: 56))
            Text("Smart Golf Caddy")
                .font(.title)
        }
    }
}
```

```swift
// ios/SmartGolfCaddyTests/SmokeTests.swift
import XCTest

final class SmokeTests: XCTestCase {
    func testTestTargetRuns() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 4: Дополнить .gitignore**

Добавить в корневой `.gitignore`:

```
# iOS
ios/SmartGolfCaddy.xcodeproj/
ios/build/
ios/Config/Local.xcconfig
ios/SmartGolfCaddy/Resources/GoogleService-Info.plist
```

- [ ] **Step 5: Сгенерировать проект и собрать**

```bash
cd ios && xcodegen
xcodebuild -project SmartGolfCaddy.xcodeproj -scheme SmartGolfCaddy \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  -derivedDataPath "$DD" build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Запустить тесты**

```bash
cd ios && xcodebuild -project SmartGolfCaddy.xcodeproj -scheme SmartGolfCaddy \
  -destination "platform=iOS Simulator,name=$SIM_NAME" \
  -derivedDataPath "$DD" test 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Запустить на симуляторе (визуальная проверка)**

```bash
xcrun simctl boot "$SIM_NAME" 2>/dev/null; open -a Simulator
xcrun simctl install booted "$DD/Build/Products/Debug-iphonesimulator/SmartGolfCaddy.app"
xcrun simctl launch booted com.dzhambulat.smartgolfcaddy
```
Expected: приложение открывается, виден гольфист и заголовок.

- [ ] **Step 8: Commit**

```bash
git add .gitignore ios/project.yml ios/Config/Local.xcconfig.example ios/SmartGolfCaddy ios/SmartGolfCaddyTests
git commit -m "feat(ios): XcodeGen skeleton — app + test targets build and run"
```

---

### Task 3: Дизайн-система Fairway Elite

**Files:**
- Create: `ios/SmartGolfCaddy/DesignSystem/DSColor.swift`
- Create: `ios/SmartGolfCaddy/DesignSystem/DSFont.swift`
- Create: `ios/SmartGolfCaddy/DesignSystem/DS.swift`
- Create: `ios/SmartGolfCaddy/Resources/Fonts/PlayfairDisplay[wght].ttf` (скачивается)
- Modify: `ios/project.yml` (UIAppFonts)
- Test: `ios/SmartGolfCaddyTests/DesignSystemTests.swift`

**Interfaces:**
- Produces: `DSColor.primary/.primaryContainer/.onPrimary/.surface/.surfaceContainer/.onSurface/.onSurfaceVariant/.outline/.error/.inversePrimary` (SwiftUI `Color`); `Color(hex: "#RRGGBB")`; `DSFont.displayLG/.headlineLG/.headlineMD/.titleLG/.bodyMD/.labelLG/.labelMD` (SwiftUI `Font`); `DS.touchTarget: CGFloat == 48`.

- [ ] **Step 1: Скачать шрифт Playfair Display (variable, OFL, есть кириллица)**

```bash
mkdir -p ios/SmartGolfCaddy/Resources/Fonts
curl -fsSL -o "ios/SmartGolfCaddy/Resources/Fonts/PlayfairDisplay[wght].ttf" \
  "https://raw.githubusercontent.com/google/fonts/main/ofl/playfairdisplay/PlayfairDisplay%5Bwght%5D.ttf"
ls -la ios/SmartGolfCaddy/Resources/Fonts/
```
Expected: файл ~300–400 KB.

- [ ] **Step 2: Зарегистрировать шрифт в project.yml**

В `ios/project.yml`, в `targets.SmartGolfCaddy.info.properties` добавить ключ:

```yaml
        UIAppFonts: ["PlayfairDisplay[wght].ttf"]
```

- [ ] **Step 3: Написать падающий тест**

```swift
// ios/SmartGolfCaddyTests/DesignSystemTests.swift
import XCTest
import SwiftUI
@testable import SmartGolfCaddy

final class DesignSystemTests: XCTestCase {
    func testPlayfairNamedInstancesAvailable() {
        // Именованные инстансы variable-шрифта видны UIKit по PostScript-имени.
        XCTAssertNotNil(UIFont(name: "PlayfairDisplay-Regular", size: 16))
        XCTAssertNotNil(UIFont(name: "PlayfairDisplay-SemiBold", size: 16))
        XCTAssertNotNil(UIFont(name: "PlayfairDisplay-Bold", size: 16))
    }

    func testHexColorParsing() {
        XCTAssertEqual(Color(hex: "#00450D"), DSColor.primary)
    }

    func testTouchTarget() {
        XCTAssertEqual(DS.touchTarget, 48)
    }
}
```

- [ ] **Step 4: Прогнать тест — убедиться, что падает**

```bash
cd ios && xcodegen && xcodebuild -project SmartGolfCaddy.xcodeproj -scheme SmartGolfCaddy \
  -destination "platform=iOS Simulator,name=$SIM_NAME" -derivedDataPath "$DD" test 2>&1 | tail -5
```
Expected: FAIL — `cannot find 'DSColor' in scope`.

- [ ] **Step 5: Реализовать дизайн-систему**

```swift
// ios/SmartGolfCaddy/DesignSystem/DSColor.swift
// Токены Fairway Elite — зеркало tailwind.config.js (веб — source of truth).
import SwiftUI

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

enum DSColor {
    static let primary = Color(hex: "#00450D")
    static let primaryContainer = Color(hex: "#1B5E20")
    static let onPrimary = Color(hex: "#FFFFFF")
    static let inversePrimary = Color(hex: "#91D78A")
    static let secondary = Color(hex: "#5E604D")
    static let secondaryContainer = Color(hex: "#E1E1C9")
    static let onSecondary = Color(hex: "#FFFFFF")
    static let tertiary = Color(hex: "#2D3D45")
    static let tertiaryContainer = Color(hex: "#44545C")
    static let onTertiary = Color(hex: "#FFFFFF")
    static let surface = Color(hex: "#F9F9F9")
    static let surfaceDim = Color(hex: "#DADADA")
    static let surfaceContainerLowest = Color(hex: "#FFFFFF")
    static let surfaceContainerLow = Color(hex: "#F3F3F4")
    static let surfaceContainer = Color(hex: "#EEEEEE")
    static let surfaceContainerHigh = Color(hex: "#E8E8E8")
    static let onSurface = Color(hex: "#1A1C1C")
    static let onSurfaceVariant = Color(hex: "#41493E")
    static let outline = Color(hex: "#717A6D")
    static let outlineVariant = Color(hex: "#C0C9BB")
    static let error = Color(hex: "#BA1A1A")
    static let errorContainer = Color(hex: "#FFDAD6")
    static let onError = Color(hex: "#FFFFFF")
}
```

```swift
// ios/SmartGolfCaddy/DesignSystem/DSFont.swift
// Один шрифт на весь UI — Playfair Display (см. Sprint 8 веба).
// Размеры/веса — зеркало fontSize из tailwind.config.js.
import SwiftUI

enum DSFont {
    static func regular(_ size: CGFloat) -> Font { .custom("PlayfairDisplay-Regular", size: size) }
    static func medium(_ size: CGFloat) -> Font { .custom("PlayfairDisplay-Medium", size: size) }
    static func semiBold(_ size: CGFloat) -> Font { .custom("PlayfairDisplay-SemiBold", size: size) }
    static func bold(_ size: CGFloat) -> Font { .custom("PlayfairDisplay-Bold", size: size) }

    static let displayLG = bold(40)
    static let headlineLG = bold(32)
    static let headlineMD = semiBold(24)
    static let titleLG = semiBold(20)
    static let bodyMD = regular(16)
    static let labelLG = semiBold(14)
    static let labelMD = medium(12)
}
```

```swift
// ios/SmartGolfCaddy/DesignSystem/DS.swift
import Foundation

enum DS {
    static let touchTarget: CGFloat = 48   // минимум для интерактивных элементов
    static let screenPadding: CGFloat = 16
    static let cornerRadius: CGFloat = 8   // rounded DEFAULT из tailwind
    static let cornerRadiusLG: CGFloat = 16
}
```

- [ ] **Step 6: Прогнать тесты — зелёные**

Run: та же команда, что в Step 4.
Expected: `** TEST SUCCEEDED **`. Если падает ТОЛЬКО `testPlayfairNamedInstancesAvailable` (именованные инстансы не видны) — заменить variable-шрифт статикой: скачать `https://gwfh.mranftl.com/api/fonts/playfair-display?download=zip&subsets=latin,cyrillic&variants=regular,500,600,700&formats=ttf`, распаковать 4 файла в `Resources/Fonts/`, перечислить их в `UIAppFonts`, использовать PostScript-имена статик (`PlayfairDisplay-Regular` и т.д. остаются те же).

- [ ] **Step 7: Commit**

```bash
git add ios/project.yml "ios/SmartGolfCaddy/Resources/Fonts/" ios/SmartGolfCaddy/DesignSystem ios/SmartGolfCaddyTests/DesignSystemTests.swift
git commit -m "feat(ios): Fairway Elite design system — colors, Playfair Display, tokens"
```

---

### Task 4: Модели (порт src/types + утилиты, TDD)

**Files:**
- Create: `ios/SmartGolfCaddy/Models/Club.swift`
- Create: `ios/SmartGolfCaddy/Models/AppUser.swift`
- Create: `ios/SmartGolfCaddy/Models/Round.swift`
- Create: `ios/SmartGolfCaddy/Models/Score.swift`
- Create: `ios/SmartGolfCaddy/Models/Intl.swift`
- Test: `ios/SmartGolfCaddyTests/ModelsTests.swift`

**Interfaces:**
- Consumes: ничего (Foundation-only, Firebase не импортировать).
- Produces (используют Tasks 5–7 и весь План 2):
  - `enum ClubCategory: String` (wood/iron/wedge/putter); `struct BagClub { id, customName?, distanceMeters: Int, enabled, category?, custom? }` + `BagClub.firestoreData: [String: Any]` + `BagClub(dict:)`
  - `enum Clubs { defaultBag: [BagClub], abbrev: [String: String], category(of:) -> ClubCategory, resolveBag(bag:legacyClubs:) -> [BagClub], label(for:in:) -> String }`
  - `struct AppUser { uid, name, avatar, handicap: Double, bag?, units?, legacyClubs? }` + `AppUser(uid:data:)` + `resolvedBag: [BagClub]`
  - `enum RoundStatus: String` (lobby/active/finished); `enum PlayMode: String`; `enum TeeColor: String` + `.multiplier`
  - `struct HoleShots { count, clubs, legacyClub?, updatedAt? }` + `resolvedClubs: [String]`; `struct PlayerInfo`; `struct HoleConfig`; `struct Round` + `Round(id:data:)` (data — уже с Date вместо Timestamp)
  - `enum Score { color(_:) -> String, onColor(_:) -> String, direction(_:) -> ScoreDirection, label(_:) -> String, metersToYards(_:) -> Int, yardsToMeters(_:) -> Int }`
  - `func pluralRu(_ n: Int, _ one: String, _ few: String, _ many: String) -> String`

- [ ] **Step 1: Написать падающие тесты**

```swift
// ios/SmartGolfCaddyTests/ModelsTests.swift
import XCTest
@testable import SmartGolfCaddy

final class ModelsTests: XCTestCase {

    // MARK: HoleShots — паритет getHoleClubs

    func testResolvedClubsCanonical() {
        let shots = HoleShots(count: 2, clubs: ["Driver", "Putter"], legacyClub: nil, updatedAt: nil)
        XCTAssertEqual(shots.resolvedClubs, ["Driver", "Putter"])
    }

    func testResolvedClubsLegacy() {
        let shots = HoleShots(count: 3, clubs: [], legacyClub: "7i", updatedAt: nil)
        XCTAssertEqual(shots.resolvedClubs, ["7i", "7i", "7i"])
    }

    func testResolvedClubsUnknown() {
        let shots = HoleShots(count: 2, clubs: [], legacyClub: nil, updatedAt: nil)
        XCTAssertEqual(shots.resolvedClubs, ["Неизвестно", "Неизвестно"])
    }

    // MARK: Clubs — паритет getBagFromUser / getClubLabel

    func testResolveBagPrefersCanonical() {
        let bag = [BagClub(id: "7i", customName: nil, distanceMeters: 140, enabled: true, category: nil, custom: nil)]
        let resolved = Clubs.resolveBag(bag: bag, legacyClubs: nil)
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved[0].category, .iron) // бэкфилл категории из id
    }

    func testResolveBagLegacyClubs() {
        let resolved = Clubs.resolveBag(bag: nil, legacyClubs: ["Driver", "Putter"])
        XCTAssertEqual(resolved.count, Clubs.defaultBag.count)
        XCTAssertTrue(resolved.first { $0.id == "Driver" }!.enabled)
        XCTAssertFalse(resolved.first { $0.id == "7i" }!.enabled)
    }

    func testResolveBagEmpty() {
        XCTAssertEqual(Clubs.resolveBag(bag: nil, legacyClubs: nil), Clubs.defaultBag)
    }

    func testClubLabels() {
        XCTAssertEqual(Clubs.label(for: "Driver", in: []), "DRV")
        XCTAssertEqual(Clubs.label(for: "custom-abc", in: []), "Клюшка")
        let bag = [BagClub(id: "custom-abc", customName: "Stealth 2", distanceMeters: 200, enabled: true, category: .wood, custom: true)]
        XCTAssertEqual(Clubs.label(for: "custom-abc", in: bag), "Stealth 2")
        XCTAssertEqual(Clubs.label(for: "Weird", in: []), "Weird")
    }

    func testDefaultBagShape() {
        XCTAssertEqual(Clubs.defaultBag.count, 20)
        XCTAssertEqual(Clubs.defaultBag.filter { $0.enabled }.count, 10)
    }

    // MARK: AppUser

    func testAppUserFromFirestoreData() {
        let user = AppUser(uid: "u1", data: [
            "name": "Джамбулат", "avatar": "https://a.jpg", "handicap": 12,
            "clubs": ["Driver", "Putter"],
        ])
        XCTAssertEqual(user?.name, "Джамбулат")
        XCTAssertEqual(user?.handicap, 12)
        XCTAssertNil(user?.bag)
        XCTAssertEqual(user?.resolvedBag.filter { $0.enabled }.count, 2)
    }

    // MARK: Round

    func testRoundFromFirestoreData() {
        let now = Date()
        let round = Round(id: "r1", data: [
            "courseId": "c1", "courseName": "Сколково", "totalHoles": 9,
            "lobbyCode": "ABC123", "status": "active", "hostId": "u1",
            "players": ["u1": ["name": "Д", "avatar": "", "totalScore": 5, "scoreDiff": 1]],
            "playerIds": ["u1"],
            "holes": [["holeNumber": 1, "par": 4, "distanceMeters": 360,
                       "shots": ["u1": ["count": 2, "clubs": ["Driver", "Putter"], "updatedAt": now]]]],
            "startedAt": now, "createdAt": now,
        ])
        XCTAssertEqual(round?.status, .active)
        XCTAssertEqual(round?.tee, .men)          // дефолт при отсутствии
        XCTAssertEqual(round?.playMode, .stroke)  // дефолт при отсутствии
        XCTAssertNil(round?.finishedAt)
        XCTAssertEqual(round?.holes.first?.shots["u1"]?.resolvedClubs, ["Driver", "Putter"])
        XCTAssertEqual(round?.players["u1"]?.totalScore, 5)
    }

    func testTeeMultipliers() {
        XCTAssertEqual(TeeColor.pro.multiplier, 1.10)
        XCTAssertEqual(TeeColor.ladies.multiplier, 0.80)
    }

    // MARK: Score — паритет scoreColor/scoreOnColor/scoreDirection/scoreLabel

    func testScorePalette() {
        XCTAssertEqual(Score.color(-2), "#FFD700"); XCTAssertEqual(Score.onColor(-2), "#1A1C1C")
        XCTAssertEqual(Score.color(-1), "#2E7D32"); XCTAssertEqual(Score.onColor(-1), "#FFFFFF")
        XCTAssertEqual(Score.color(0), "#FFFFFF");  XCTAssertEqual(Score.onColor(0), "#1A1C1C")
        XCTAssertEqual(Score.color(1), "#EF6C00");  XCTAssertEqual(Score.onColor(1), "#1A1C1C")
        XCTAssertEqual(Score.color(3), "#C62828");  XCTAssertEqual(Score.onColor(3), "#FFFFFF")
    }

    func testScoreDirectionAndLabel() {
        XCTAssertEqual(Score.direction(-1), .under)
        XCTAssertEqual(Score.direction(0), .par)
        XCTAssertEqual(Score.direction(2), .over)
        XCTAssertEqual(Score.label(-2), "Eagle")
        XCTAssertEqual(Score.label(4), "+4")
    }

    func testUnits() {
        XCTAssertEqual(Score.metersToYards(100), 109)
        XCTAssertEqual(Score.yardsToMeters(109), 100)
    }

    // MARK: pluralRu

    func testPluralRu() {
        XCTAssertEqual(pluralRu(1, "лунка", "лунки", "лунок"), "лунка")
        XCTAssertEqual(pluralRu(3, "лунка", "лунки", "лунок"), "лунки")
        XCTAssertEqual(pluralRu(5, "лунка", "лунки", "лунок"), "лунок")
        XCTAssertEqual(pluralRu(11, "лунка", "лунки", "лунок"), "лунок")
        XCTAssertEqual(pluralRu(21, "лунка", "лунки", "лунок"), "лунка")
    }
}
```

- [ ] **Step 2: Прогнать — убедиться, что падает компиляцией**

Run: стандартная тест-команда из Task 2 Step 6.
Expected: FAIL — `cannot find 'HoleShots' in scope` и т.п.

- [ ] **Step 3: Реализовать модели**

```swift
// ios/SmartGolfCaddy/Models/Club.swift
// Зеркало src/types/index.ts (клюшки). Веб — source of truth.
import Foundation

enum ClubCategory: String, Codable {
    case wood, iron, wedge, putter
}

struct BagClub: Equatable, Identifiable {
    var id: String
    var customName: String?
    var distanceMeters: Int
    var enabled: Bool
    var category: ClubCategory?
    var custom: Bool?

    init(id: String, customName: String?, distanceMeters: Int, enabled: Bool,
         category: ClubCategory?, custom: Bool?) {
        self.id = id
        self.customName = customName
        self.distanceMeters = distanceMeters
        self.enabled = enabled
        self.category = category
        self.custom = custom
    }

    init?(dict: [String: Any]) {
        guard let id = dict["id"] as? String else { return nil }
        self.id = id
        customName = dict["customName"] as? String
        distanceMeters = (dict["distanceMeters"] as? NSNumber)?.intValue ?? 0
        enabled = dict["enabled"] as? Bool ?? false
        category = (dict["category"] as? String).flatMap(ClubCategory.init(rawValue:))
        custom = dict["custom"] as? Bool
    }

    var firestoreData: [String: Any] {
        var d: [String: Any] = ["id": id, "distanceMeters": distanceMeters, "enabled": enabled]
        if let customName { d["customName"] = customName }
        if let category { d["category"] = category.rawValue }
        if let custom { d["custom"] = custom }
        return d
    }
}

enum Clubs {
    static let abbrev: [String: String] = [
        "Driver": "DRV", "3W": "3W", "5W": "5W", "Hybrid": "HY",
        "3i": "3i", "4i": "4i", "5i": "5i", "6i": "6i", "7i": "7i", "8i": "8i", "9i": "9i",
        "PW": "PW", "GW": "GW", "SW": "SW", "LW": "LW",
        "50°": "50°", "54°": "54°", "58°": "58°", "60°": "60°",
        "Putter": "PT",
    ]

    static let groups: [(category: ClubCategory, label: String, defaultIds: [String])] = [
        (.wood, "Драйвер и вуды", ["Driver", "3W", "5W", "Hybrid"]),
        (.iron, "Айроны", ["3i", "4i", "5i", "6i", "7i", "8i", "9i"]),
        (.wedge, "Вейджи", ["PW", "GW", "50°", "SW", "54°", "58°", "LW", "60°"]),
        (.putter, "Паттер", ["Putter"]),
    ]

    static let defaultBag: [BagClub] = [
        BagClub(id: "Driver", customName: nil, distanceMeters: 230, enabled: true, category: .wood, custom: nil),
        BagClub(id: "3W", customName: nil, distanceMeters: 210, enabled: true, category: .wood, custom: nil),
        BagClub(id: "5W", customName: nil, distanceMeters: 195, enabled: false, category: .wood, custom: nil),
        BagClub(id: "Hybrid", customName: nil, distanceMeters: 185, enabled: false, category: .wood, custom: nil),
        BagClub(id: "3i", customName: nil, distanceMeters: 185, enabled: false, category: .iron, custom: nil),
        BagClub(id: "4i", customName: nil, distanceMeters: 175, enabled: false, category: .iron, custom: nil),
        BagClub(id: "5i", customName: nil, distanceMeters: 165, enabled: true, category: .iron, custom: nil),
        BagClub(id: "6i", customName: nil, distanceMeters: 150, enabled: true, category: .iron, custom: nil),
        BagClub(id: "7i", customName: nil, distanceMeters: 140, enabled: true, category: .iron, custom: nil),
        BagClub(id: "8i", customName: nil, distanceMeters: 125, enabled: true, category: .iron, custom: nil),
        BagClub(id: "9i", customName: nil, distanceMeters: 110, enabled: true, category: .iron, custom: nil),
        BagClub(id: "PW", customName: nil, distanceMeters: 95, enabled: true, category: .wedge, custom: nil),
        BagClub(id: "GW", customName: nil, distanceMeters: 85, enabled: false, category: .wedge, custom: nil),
        BagClub(id: "50°", customName: nil, distanceMeters: 85, enabled: false, category: .wedge, custom: nil),
        BagClub(id: "SW", customName: nil, distanceMeters: 70, enabled: true, category: .wedge, custom: nil),
        BagClub(id: "54°", customName: nil, distanceMeters: 75, enabled: false, category: .wedge, custom: nil),
        BagClub(id: "58°", customName: nil, distanceMeters: 60, enabled: false, category: .wedge, custom: nil),
        BagClub(id: "LW", customName: nil, distanceMeters: 55, enabled: false, category: .wedge, custom: nil),
        BagClub(id: "60°", customName: nil, distanceMeters: 55, enabled: false, category: .wedge, custom: nil),
        BagClub(id: "Putter", customName: nil, distanceMeters: 0, enabled: true, category: .putter, custom: nil),
    ]

    static func category(of club: BagClub) -> ClubCategory {
        if let category = club.category { return category }
        for group in groups where group.defaultIds.contains(club.id) { return group.category }
        return .iron
    }

    static func resolveBag(bag: [BagClub]?, legacyClubs: [String]?) -> [BagClub] {
        if let bag, !bag.isEmpty {
            return bag.map { club in
                if club.category != nil { return club }
                var patched = club
                patched.category = category(of: club)
                return patched
            }
        }
        if let legacyClubs, !legacyClubs.isEmpty {
            let enabled = Set(legacyClubs)
            return defaultBag.map { club in
                var patched = club
                patched.enabled = enabled.contains(club.id)
                return patched
            }
        }
        return defaultBag
    }

    static func label(for clubId: String, in bag: [BagClub]) -> String {
        if let known = abbrev[clubId] { return known }
        if let club = bag.first(where: { $0.id == clubId }),
           let name = club.customName, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        if clubId.hasPrefix("custom-") { return "Клюшка" }
        return clubId
    }
}
```

```swift
// ios/SmartGolfCaddy/Models/AppUser.swift
import Foundation

enum DistanceUnit: String, Codable {
    case m, yd
}

struct AppUser: Equatable {
    let uid: String
    var name: String
    var avatar: String
    var handicap: Double
    var bag: [BagClub]?
    var units: DistanceUnit?
    var legacyClubs: [String]?   // Firestore-ключ "clubs" (pre-bag rollout)

    var resolvedBag: [BagClub] { Clubs.resolveBag(bag: bag, legacyClubs: legacyClubs) }

    init?(uid: String, data: [String: Any]) {
        self.uid = uid
        name = data["name"] as? String ?? "Golfer"
        avatar = data["avatar"] as? String ?? ""
        handicap = (data["handicap"] as? NSNumber)?.doubleValue ?? 0
        if let rawBag = data["bag"] as? [[String: Any]] {
            let parsed = rawBag.compactMap(BagClub.init(dict:))
            bag = parsed.isEmpty ? nil : parsed
        }
        units = (data["units"] as? String).flatMap(DistanceUnit.init(rawValue:))
        legacyClubs = data["clubs"] as? [String]
    }
}
```

```swift
// ios/SmartGolfCaddy/Models/Round.swift
// Зеркало src/types/index.ts (раунд). data-словари приходят из Services
// УЖЕ с Date вместо Firestore Timestamp (см. FirebaseService.normalizedDates).
import Foundation

enum RoundStatus: String {
    case lobby, active, finished
}

enum PlayMode: String {
    case stroke, match
}

enum TeeColor: String, CaseIterable {
    case pro, men, senior, ladies

    var multiplier: Double {
        switch self {
        case .pro: return 1.10
        case .men: return 1.00
        case .senior: return 0.90
        case .ladies: return 0.80
        }
    }
}

struct HoleShots: Equatable {
    var count: Int
    var clubs: [String]
    var legacyClub: String?   // Firestore-ключ "club" (старые раунды)
    var updatedAt: Date?

    // Паритет getHoleClubs из src/types/index.ts
    var resolvedClubs: [String] {
        if !clubs.isEmpty { return clubs }
        if let legacyClub { return Array(repeating: legacyClub, count: count) }
        return Array(repeating: "Неизвестно", count: count)
    }

    init(count: Int, clubs: [String], legacyClub: String?, updatedAt: Date?) {
        self.count = count
        self.clubs = clubs
        self.legacyClub = legacyClub
        self.updatedAt = updatedAt
    }

    init?(data: [String: Any]) {
        count = (data["count"] as? NSNumber)?.intValue ?? 0
        clubs = data["clubs"] as? [String] ?? []
        legacyClub = data["club"] as? String
        updatedAt = data["updatedAt"] as? Date
    }
}

struct PlayerInfo: Equatable {
    var name: String
    var avatar: String
    var totalScore: Int
    var scoreDiff: Int
    var email: String?

    init?(data: [String: Any]) {
        name = data["name"] as? String ?? ""
        avatar = data["avatar"] as? String ?? ""
        totalScore = (data["totalScore"] as? NSNumber)?.intValue ?? 0
        scoreDiff = (data["scoreDiff"] as? NSNumber)?.intValue ?? 0
        email = data["email"] as? String
    }
}

struct HoleConfig: Equatable {
    var holeNumber: Int
    var par: Int
    var distanceMeters: Int
    var shots: [String: HoleShots]

    init?(data: [String: Any]) {
        holeNumber = (data["holeNumber"] as? NSNumber)?.intValue ?? 0
        par = (data["par"] as? NSNumber)?.intValue ?? 4
        distanceMeters = (data["distanceMeters"] as? NSNumber)?.intValue ?? 0
        var parsed: [String: HoleShots] = [:]
        for (uid, raw) in data["shots"] as? [String: [String: Any]] ?? [:] {
            parsed[uid] = HoleShots(data: raw)
        }
        shots = parsed
    }
}

struct Round: Equatable, Identifiable {
    let id: String
    var courseId: String
    var courseName: String
    var totalHoles: Int
    var lobbyCode: String
    var status: RoundStatus
    var hostId: String
    var players: [String: PlayerInfo]
    var playerIds: [String]
    var tee: TeeColor
    var playMode: PlayMode
    var holes: [HoleConfig]
    var startedAt: Date?    // nil, пока групповой раунд в лобби
    var finishedAt: Date?
    var createdAt: Date

    // Паритет normalizeRound из src/services/rounds.ts
    init?(id: String, data: [String: Any]) {
        guard let statusRaw = data["status"] as? String,
              let status = RoundStatus(rawValue: statusRaw) else { return nil }
        self.id = id
        self.status = status
        courseId = data["courseId"] as? String ?? ""
        courseName = data["courseName"] as? String ?? ""
        totalHoles = (data["totalHoles"] as? NSNumber)?.intValue ?? 18
        lobbyCode = data["lobbyCode"] as? String ?? ""
        hostId = data["hostId"] as? String ?? ""
        var parsedPlayers: [String: PlayerInfo] = [:]
        for (uid, raw) in data["players"] as? [String: [String: Any]] ?? [:] {
            parsedPlayers[uid] = PlayerInfo(data: raw)
        }
        players = parsedPlayers
        playerIds = data["playerIds"] as? [String] ?? []
        tee = (data["tee"] as? String).flatMap(TeeColor.init(rawValue:)) ?? .men
        playMode = (data["playMode"] as? String).flatMap(PlayMode.init(rawValue:)) ?? .stroke
        holes = (data["holes"] as? [[String: Any]] ?? []).compactMap(HoleConfig.init(data:))
        startedAt = data["startedAt"] as? Date
        finishedAt = data["finishedAt"] as? Date
        createdAt = data["createdAt"] as? Date ?? Date()
    }
}
```

```swift
// ios/SmartGolfCaddy/Models/Score.swift
// Паритет scoreColor/scoreOnColor/scoreDirection/scoreLabel из src/types.
// Возвращают hex-строки — UI мапит через Color(hex:). Пары цвет+текст
// подобраны под WCAG AA, не менять по отдельности.
import Foundation

enum ScoreDirection {
    case under, par, over
}

enum Score {
    static func color(_ delta: Int) -> String {
        if delta <= -2 { return "#FFD700" }
        if delta == -1 { return "#2E7D32" }
        if delta == 0 { return "#FFFFFF" }
        if delta == 1 { return "#EF6C00" }
        return "#C62828"
    }

    static func onColor(_ delta: Int) -> String {
        if delta <= -2 { return "#1A1C1C" }
        if delta == -1 { return "#FFFFFF" }
        if delta == 0 { return "#1A1C1C" }
        if delta == 1 { return "#1A1C1C" }
        return "#FFFFFF"
    }

    static func direction(_ delta: Int) -> ScoreDirection {
        if delta < 0 { return .under }
        if delta == 0 { return .par }
        return .over
    }

    static func label(_ delta: Int) -> String {
        if delta <= -2 { return "Eagle" }
        if delta == -1 { return "Birdie" }
        if delta == 0 { return "Par" }
        if delta == 1 { return "Bogey" }
        if delta == 2 { return "Double" }
        return "+\(delta)"
    }

    static func metersToYards(_ m: Int) -> Int {
        Int((Double(m) * 1.0936).rounded())
    }

    static func yardsToMeters(_ y: Int) -> Int {
        Int((Double(y) / 1.0936).rounded())
    }
}
```

```swift
// ios/SmartGolfCaddy/Models/Intl.swift
// Паритет pluralRu из src/utils/intl.ts.
import Foundation

func pluralRu(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let absN = abs(n)
    let mod10 = absN % 10
    let mod100 = absN % 100
    if mod10 == 1 && mod100 != 11 { return one }
    if mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) { return few }
    return many
}
```

- [ ] **Step 4: Прогнать тесты — зелёные**

Run: стандартная тест-команда.
Expected: `** TEST SUCCEEDED **`, все тесты ModelsTests зелёные.

- [ ] **Step 5: Commit**

```bash
git add ios/SmartGolfCaddy/Models ios/SmartGolfCaddyTests/ModelsTests.swift
git commit -m "feat(ios): models — port of src/types with legacy-field parity + tests"
```

---

### Task 5: Firebase-подключение + App Check debug

**Files:**
- Create: `ios/SmartGolfCaddy/App/AppDelegate.swift`
- Create: `ios/SmartGolfCaddy/Services/FirebaseService.swift`
- Create: `ios/SmartGolfCaddy/Resources/GoogleService-Info.plist` (из Firebase, не в git)
- Modify: `ios/project.yml` (SPM-пакеты, URL scheme)
- Modify: `ios/SmartGolfCaddy/App/SmartGolfCaddyApp.swift` (AppDelegate adaptor)
- Modify: `ios/Config/Local.xcconfig` (GOOGLE_REVERSED_CLIENT_ID)
- Test: `ios/SmartGolfCaddyTests/FirebaseServiceTests.swift`

**Interfaces:**
- Consumes: Models (Task 4).
- Produces: `FirebaseService.db: Firestore`, `FirebaseService.functions: Functions` (регион us-central1), `FirebaseService.normalizedDates(_ value: Any) -> Any` (рекурсивно Timestamp→Date); настроенный `FirebaseApp` c App Check debug provider в DEBUG-сборках.

- [ ] **Step 1: Зарегистрировать iOS-приложение в Firebase и скачать конфиг**

```bash
source ~/.nvm/nvm.sh
firebase apps:create ios "Smart Golf Caddy iOS" \
  --bundle-id com.dzhambulat.smartgolfcaddy --project smart-golf-caddy
# Из вывода взять App ID вида 1:XXXX:ios:YYYY и подставить:
firebase apps:sdkconfig ios <APP_ID> --project smart-golf-caddy \
  > ios/SmartGolfCaddy/Resources/GoogleService-Info.plist
plutil -lint ios/SmartGolfCaddy/Resources/GoogleService-Info.plist
```
Expected: `OK`. Если `apps:sdkconfig` выводит обёртку вместо чистого plist — скачать файл руками из Firebase console (Project settings → Your apps → iOS) и положить по тому же пути.

- [ ] **Step 2: Проверить REVERSED_CLIENT_ID и записать в Local.xcconfig**

```bash
REV_ID=$(/usr/libexec/PlistBuddy -c "Print :REVERSED_CLIENT_ID" ios/SmartGolfCaddy/Resources/GoogleService-Info.plist)
echo "$REV_ID"
sed -i '' "s|^GOOGLE_REVERSED_CLIENT_ID.*|GOOGLE_REVERSED_CLIENT_ID = $REV_ID|" ios/Config/Local.xcconfig
cat ios/Config/Local.xcconfig
```
Expected: значение вида `com.googleusercontent.apps.…`. Если ключа в plist НЕТ — в Firebase console убедиться, что Google-провайдер включён в Authentication → Sign-in method (для веба уже включён), и заново скачать plist из console.

- [ ] **Step 3: Добавить SPM-пакеты и URL scheme в project.yml**

В `ios/project.yml` добавить на верхний уровень:

```yaml
packages:
  Firebase:
    url: https://github.com/firebase/firebase-ios-sdk
    from: 12.0.0
  GoogleSignIn:
    url: https://github.com/google/GoogleSignIn-iOS
    from: 8.0.0
```

В `targets.SmartGolfCaddy` добавить:

```yaml
    dependencies:
      - package: Firebase
        product: FirebaseAuth
      - package: Firebase
        product: FirebaseFirestore
      - package: Firebase
        product: FirebaseFunctions
      - package: Firebase
        product: FirebaseAppCheck
      - package: GoogleSignIn
        product: GoogleSignIn
```

В `targets.SmartGolfCaddyTests` заменить блок `dependencies` (иначе `import FirebaseFirestore` в FirebaseServiceTests не соберётся):

```yaml
    dependencies:
      - target: SmartGolfCaddy
      - package: Firebase
        product: FirebaseFirestore
```

В `targets.SmartGolfCaddy.info.properties` добавить:

```yaml
        CFBundleURLTypes:
          - CFBundleURLSchemes: ["$(GOOGLE_REVERSED_CLIENT_ID)"]
```

- [ ] **Step 4: AppDelegate + FirebaseService**

```swift
// ios/SmartGolfCaddy/App/AppDelegate.swift
import FirebaseAppCheck
import FirebaseCore
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if DEBUG
        // Debug provider ДО configure() — иначе SDK попытается App Attest.
        // Токен из консоли Xcode регистрируется в Firebase console → App Check.
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #endif
        FirebaseApp.configure()
        return true
    }
}
```

```swift
// ios/SmartGolfCaddy/Services/FirebaseService.swift
// Единственная точка доступа к Firebase-инстансам (зеркало src/firebase.ts).
import FirebaseFirestore
import FirebaseFunctions

enum FirebaseService {
    static var db: Firestore { Firestore.firestore() }

    // Функции живут в us-central1 (Firestore — europe-west3, это ожидаемо).
    static let functions = Functions.functions(region: "us-central1")

    // Рекурсивно заменяет Firestore Timestamp на Date во вложенных
    // словарях/массивах — аналог normalizeRound на границе Services.
    static func normalizedDates(_ value: Any) -> Any {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        if let dict = value as? [String: Any] { return dict.mapValues(normalizedDates) }
        if let array = value as? [Any] { return array.map(normalizedDates) }
        return value
    }
}
```

```swift
// ios/SmartGolfCaddy/App/SmartGolfCaddyApp.swift — заменить целиком
import SwiftUI

@main
struct SmartGolfCaddyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup { RootView() }
    }
}
```

- [ ] **Step 5: Тест на normalizedDates**

```swift
// ios/SmartGolfCaddyTests/FirebaseServiceTests.swift
import FirebaseFirestore
import XCTest
@testable import SmartGolfCaddy

final class FirebaseServiceTests: XCTestCase {
    func testNormalizedDatesRecursion() {
        let ts = Timestamp(date: Date(timeIntervalSince1970: 1_000_000))
        let input: [String: Any] = [
            "createdAt": ts,
            "holes": [["shots": ["u1": ["updatedAt": ts]]]],
            "name": "x",
        ]
        let output = FirebaseService.normalizedDates(input) as! [String: Any]
        XCTAssertTrue(output["createdAt"] is Date)
        let holes = output["holes"] as! [[String: Any]]
        let shots = holes[0]["shots"] as! [String: [String: Any]]
        XCTAssertTrue(shots["u1"]!["updatedAt"] is Date)
        XCTAssertEqual(output["name"] as? String, "x")
    }
}
```

- [ ] **Step 6: Пересобрать (первый раз долго — SPM резолвит ~5–10 мин) и прогнать тесты**

```bash
cd ios && xcodegen
xcodebuild -project SmartGolfCaddy.xcodeproj -resolvePackageDependencies 2>&1 | tail -3
xcodebuild -project SmartGolfCaddy.xcodeproj -scheme SmartGolfCaddy \
  -destination "platform=iOS Simulator,name=$SIM_NAME" -derivedDataPath "$DD" test 2>&1 | tail -5
```
Expected: `** TEST SUCCEEDED **`. Запустить app на симуляторе (команды из Task 2 Step 7) — в логах Xcode-консоли (`xcrun simctl launch --console-pty booted com.dzhambulat.smartgolfcaddy | head -40`) появляется строка `Firebase App Check debug token: '<UUID>'`. Сохранить токен — нужен в Task 7.

- [ ] **Step 7: Commit**

```bash
git add ios/project.yml ios/SmartGolfCaddy/App ios/SmartGolfCaddy/Services/FirebaseService.swift ios/SmartGolfCaddyTests/FirebaseServiceTests.swift
git commit -m "feat(ios): Firebase SDK wiring — App Check debug provider, us-central1 functions"
```

---

### Task 6: Auth — Google Sign-In, профиль, экран входа

**Files:**
- Create: `ios/SmartGolfCaddy/Services/AuthService.swift`
- Create: `ios/SmartGolfCaddy/Services/ProfileService.swift`
- Create: `ios/SmartGolfCaddy/ViewModels/SessionViewModel.swift`
- Create: `ios/SmartGolfCaddy/Views/AuthView.swift`
- Create: `ios/SmartGolfCaddy/Views/HomePlaceholderView.swift`
- Modify: `ios/SmartGolfCaddy/App/RootView.swift`

**Interfaces:**
- Consumes: `AppUser`, `Clubs.defaultBag`, `BagClub.firestoreData` (Task 4); `FirebaseService` (Task 5); `DSColor`/`DSFont`/`DS` (Task 3).
- Produces:
  - `AuthService.currentUserId: String?`; `AuthService.subscribe(_ cb: @escaping (String?) -> Void) -> () -> Void` (колбэк получает uid или nil, возврат — отписка); `AuthService.signInWithGoogle() async throws` (сам находит presenting VC, создаёт профиль при первом входе); `AuthService.signOut() throws`
  - `ProfileService.subscribeToProfile(uid:onChange:onError:) -> () -> Void`
  - `SessionViewModel` (@Observable): `state: .loading/.signedOut/.signedIn`, `profile: AppUser?`, `errorMessage: String?`, `start()`, `signIn() async`, `signOut()`

- [ ] **Step 1: AuthService**

```swift
// ios/SmartGolfCaddy/Services/AuthService.swift
// Зеркало src/services/auth.ts: Google-вход + создание профиля при
// первом входе. Наружу отдаёт только uid и замыкание-отписку — слои
// выше не видят типов Firebase.
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn
import UIKit

enum AuthServiceError: LocalizedError {
    case noPresenter
    case missingToken

    var errorDescription: String? {
        switch self {
        case .noPresenter: return "Не найден корневой экран для входа"
        case .missingToken: return "Google не вернул токен — попробуйте ещё раз"
        }
    }
}

@MainActor
enum AuthService {
    static var currentUserId: String? { Auth.auth().currentUser?.uid }

    static func subscribe(_ callback: @escaping (String?) -> Void) -> () -> Void {
        let handle = Auth.auth().addStateDidChangeListener { _, user in
            callback(user?.uid)
        }
        return { Auth.auth().removeStateDidChangeListener(handle) }
    }

    static func signInWithGoogle() async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthServiceError.missingToken
        }
        guard let presenter = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first else {
            throw AuthServiceError.noPresenter
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthServiceError.missingToken
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        let authResult = try await Auth.auth().signIn(with: credential)
        try await ensureProfile(
            uid: authResult.user.uid,
            name: authResult.user.displayName,
            avatar: authResult.user.photoURL?.absoluteString
        )
    }

    // Паритет signInWithGoogle из auth.ts: профиль создаётся один раз,
    // с каноничным bag (не legacy clubs).
    static func ensureProfile(uid: String, name: String?, avatar: String?) async throws {
        let ref = FirebaseService.db.collection("users").document(uid)
        let snapshot = try await ref.getDocument()
        guard !snapshot.exists else { return }
        try await ref.setData([
            "name": name ?? "Golfer",
            "avatar": avatar ?? "",
            "handicap": 0,
            "bag": Clubs.defaultBag.map { $0.firestoreData },
            "createdAt": FieldValue.serverTimestamp(),
        ])
    }

    static func signOut() throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
    }
}
```

- [ ] **Step 2: ProfileService**

```swift
// ios/SmartGolfCaddy/Services/ProfileService.swift
// Подписка на профиль. onError ОБЯЗАТЕЛЕН у вызывающего — иначе ошибка
// прав/сети превращается в вечный спиннер (правило из веб-версии).
import FirebaseFirestore

enum ProfileService {
    static func subscribeToProfile(
        uid: String,
        onChange: @escaping (AppUser?) -> Void,
        onError: @escaping (Error) -> Void
    ) -> () -> Void {
        let listener = FirebaseService.db.collection("users").document(uid)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onError(error)
                    return
                }
                guard let snapshot, snapshot.exists, let raw = snapshot.data() else {
                    onChange(nil)
                    return
                }
                let data = FirebaseService.normalizedDates(raw) as? [String: Any] ?? raw
                onChange(AppUser(uid: snapshot.documentID, data: data))
            }
        return { listener.remove() }
    }
}
```

- [ ] **Step 3: SessionViewModel**

```swift
// ios/SmartGolfCaddy/ViewModels/SessionViewModel.swift
import Foundation
import Observation

@Observable
@MainActor
final class SessionViewModel {
    enum State {
        case loading, signedOut, signedIn
    }

    var state: State = .loading
    var profile: AppUser?
    var errorMessage: String?

    private var unsubscribeAuth: (() -> Void)?
    private var unsubscribeProfile: (() -> Void)?

    func start() {
        unsubscribeAuth = AuthService.subscribe { [weak self] uid in
            guard let self else { return }
            self.unsubscribeProfile?()
            self.unsubscribeProfile = nil
            self.profile = nil
            guard let uid else {
                self.state = .signedOut
                return
            }
            self.state = .signedIn
            self.unsubscribeProfile = ProfileService.subscribeToProfile(
                uid: uid,
                onChange: { [weak self] user in self?.profile = user },
                onError: { [weak self] _ in
                    self?.errorMessage = "Не удалось загрузить профиль — проверьте сеть"
                }
            )
        }
    }

    func signIn() async {
        errorMessage = nil
        do {
            try await AuthService.signInWithGoogle()
        } catch is CancellationError {
            // пользователь закрыл окно входа — не ошибка
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        do {
            try AuthService.signOut()
        } catch {
            errorMessage = "Не удалось выйти — попробуйте ещё раз"
        }
    }
}
```

- [ ] **Step 4: AuthView, HomePlaceholderView, RootView**

```swift
// ios/SmartGolfCaddy/Views/AuthView.swift
import SwiftUI

struct AuthView: View {
    @Environment(SessionViewModel.self) private var session

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "figure.golf")
                .font(.system(size: 64))
                .foregroundStyle(DSColor.primary)
            Text("Smart Golf Caddy")
                .font(DSFont.headlineLG)
                .foregroundStyle(DSColor.onSurface)
            Text("Трекинг гольф-раундов")
                .font(DSFont.bodyMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
            Spacer()
            if let message = session.errorMessage {
                Text(message)
                    .font(DSFont.labelMD)
                    .foregroundStyle(DSColor.error)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.screenPadding)
            }
            Button {
                Task { await session.signIn() }
            } label: {
                Text("ВОЙТИ ЧЕРЕЗ GOOGLE")
                    .font(DSFont.labelLG)
                    .tracking(1.5)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DS.touchTarget)
            }
            .background(DSColor.primary)
            .foregroundStyle(DSColor.onPrimary)
            .clipShape(Capsule())
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.surface)
    }
}
```

```swift
// ios/SmartGolfCaddy/Views/HomePlaceholderView.swift
// Временный Home — План 2 заменит полноценным экраном.
import SwiftUI

struct HomePlaceholderView: View {
    @Environment(SessionViewModel.self) private var session

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.crop.circle")
                .font(.system(size: 48))
                .foregroundStyle(DSColor.primary)
            Text("Привет, \(session.profile?.name ?? "…")!")
                .font(DSFont.headlineMD)
                .foregroundStyle(DSColor.onSurface)
            Text("Клюшек в сумке: \(session.profile?.resolvedBag.filter(\.enabled).count ?? 0)")
                .font(DSFont.bodyMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
            #if DEBUG
            EmptyView() // Task 7 заменит на DiagnosticsView()
            #endif
            Spacer()
            Button {
                session.signOut()
            } label: {
                Text("ВЫЙТИ")
                    .font(DSFont.labelLG)
                    .tracking(1.5)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DS.touchTarget)
            }
            .background(DSColor.surfaceContainer)
            .foregroundStyle(DSColor.onSurface)
            .clipShape(Capsule())
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.surface)
    }
}
```

Примечание: `EmptyView()` — плейсхолдер; Task 7 Step 2 заменит его на `DiagnosticsView()`.

```swift
// ios/SmartGolfCaddy/App/RootView.swift — заменить целиком
import GoogleSignIn
import SwiftUI

struct RootView: View {
    @State private var session = SessionViewModel()

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ProgressView()
            case .signedOut:
                AuthView()
            case .signedIn:
                HomePlaceholderView()
            }
        }
        .environment(session)
        .task { session.start() }
        .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
    }
}
```

Примечание: `import GoogleSignIn` в RootView — единственное разрешённое исключение вне Services (обработка redirect-URL входа), аналог узаконенного импорта в AppDelegate.

- [ ] **Step 5: Собрать и проверить вход на симуляторе**

```bash
cd ios && xcodegen && xcodebuild -project SmartGolfCaddy.xcodeproj -scheme SmartGolfCaddy \
  -destination "platform=iOS Simulator,name=$SIM_NAME" -derivedDataPath "$DD" build 2>&1 | tail -3
xcrun simctl install booted "$DD/Build/Products/Debug-iphonesimulator/SmartGolfCaddy.app"
xcrun simctl launch booted com.dzhambulat.smartgolfcaddy
```
Expected: экран входа в стиле Fairway Elite. Тап «ВОЙТИ ЧЕРЕЗ GOOGLE» → web-форма Google → после входа экран «Привет, <имя>!» с числом клюшек (для нового uid — 10: дефолтная сумка). Проверить в Firebase console → Firestore → `users/<uid>`, что документ создан с `bag` (20 элементов) и `createdAt`.

- [ ] **Step 6: Прогнать все тесты**

Run: стандартная тест-команда.
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add ios/SmartGolfCaddy/Services ios/SmartGolfCaddy/ViewModels ios/SmartGolfCaddy/Views ios/SmartGolfCaddy/App/RootView.swift
git commit -m "feat(ios): Google sign-in + profile bootstrap + auth screen"
```

---

### Task 7: Интеграционный смоук — App Check, callable, iPhone

**Files:**
- Create: `ios/SmartGolfCaddy/Services/CallableContracts.swift`
- Create: `ios/SmartGolfCaddy/Views/DiagnosticsView.swift`
- Modify: `ios/SmartGolfCaddy/Views/HomePlaceholderView.swift` (включить DiagnosticsView)
- Modify: `src/types/callable.ts` (SYNC-маркер)
- Modify: `functions/src/contracts.ts` (SYNC-маркер)

**Interfaces:**
- Consumes: `FirebaseService.functions` (Task 5).
- Produces: `RecordShotInput/UpdateHoleConfigInput/JoinLobbyInput/ShareInput` (Encodable-структуры, зеркало Zod-контрактов); `func callableDict<T: Encodable>(_ value: T) throws -> [String: Any]`; работающий канал app → App Check → callable, проверенный на симуляторе и iPhone.

- [ ] **Step 1: Контракты callable + сериализация**

```swift
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
```

- [ ] **Step 2: DiagnosticsView**

```swift
// ios/SmartGolfCaddy/Views/DiagnosticsView.swift
// DEBUG-only: проверяет канал app → App Check → callable. Ожидаемый
// успех: joinLobbyByCode с несуществующим кодом возвращает roundId: null.
// Ошибка unauthenticated = App Check не пропустил (проверить debug token).
import FirebaseFunctions
import SwiftUI

struct DiagnosticsView: View {
    @State private var status = "Проверка связи не запускалась"
    @State private var running = false

    var body: some View {
        VStack(spacing: 8) {
            Button {
                Task { await runCheck() }
            } label: {
                Label("Проверить связь с сервером", systemImage: "antenna.radiowaves.left.and.right")
                    .font(DSFont.labelLG)
                    .frame(minHeight: DS.touchTarget)
            }
            .disabled(running)
            Text(status)
                .font(DSFont.labelMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
                .multilineTextAlignment(.center)
        }
        .padding(DS.screenPadding)
    }

    private func runCheck() async {
        running = true
        defer { running = false }
        do {
            let payload = try callableDict(JoinLobbyInput(code: "ZZZZZZ"))
            let result = try await FirebaseService.functions
                .httpsCallable("joinLobbyByCode").call(payload)
            let data = result.data as? [String: Any]
            if data?["roundId"] is NSNull || data?["roundId"] == nil {
                status = "Сервер отвечает, App Check пропускает. Канал работает."
            } else {
                status = "Неожиданный ответ: \(String(describing: result.data))"
            }
        } catch {
            let ns = error as NSError
            if ns.domain == FunctionsErrorDomain,
               ns.code == FunctionsErrorCode.unauthenticated.rawValue {
                status = "App Check отклонил вызов — зарегистрируйте debug token в консоли Firebase"
            } else {
                status = "Ошибка: \(error.localizedDescription)"
            }
        }
    }
}
```

Примечание: `DiagnosticsView` импортирует FirebaseFunctions — вью DEBUG-only и не попадает в релиз; это осознанное отступление от services-only ради простоты диагностики. В `HomePlaceholderView` заменить `EmptyView()` на `DiagnosticsView()`.

- [ ] **Step 3: Зарегистрировать debug token и проверить канал на симуляторе**

1. Запустить app с консолью: `xcrun simctl launch --console-pty booted com.dzhambulat.smartgolfcaddy | grep -m1 "App Check debug token"` (или найти в выводе Xcode).
2. РУЧНОЙ ШАГ (пользователь): Firebase console → App Check → Apps → «Smart Golf Caddy iOS» → меню ⋮ → Manage debug tokens → Add token → вставить UUID из шага 1, имя «Simulator dev».
3. Перезапустить приложение, войти, нажать «Проверить связь с сервером».

Expected: «Сервер отвечает, App Check пропускает. Канал работает.» Если «App Check отклонил вызов» — токен не зарегистрирован/опечатка; повторить шаг 2.

- [ ] **Step 4: SYNC-маркеры в TS-файлах**

```bash
perl -0pi -e 's|// SYNC: keep these in lockstep with the server schemas\.|// SYNC: keep these in lockstep with the server schemas AND the iOS\n// mirror in ios/SmartGolfCaddy/Services/CallableContracts.swift.|' src/types/callable.ts
grep -n "ios/SmartGolfCaddy" src/types/callable.ts
```
Expected: строка найдена. Затем то же для серверного файла:

```bash
perl -0pi -e 's|// `src/types/callable\.ts`\. When you change a schema here, update the\n// matching type on the client\.|// `src/types/callable.ts` and as Swift structs in\n// `ios/SmartGolfCaddy/Services/CallableContracts.swift`. When you change a\n// schema here, update both mirrors.|' functions/src/contracts.ts
grep -n "ios/SmartGolfCaddy" functions/src/contracts.ts
```

Expected: grep находит строку с путём Swift-файла.

- [ ] **Step 5: Прогнать веб-проверки (не сломали ли TS)**

```bash
source ~/.nvm/nvm.sh
npx tsc --noEmit && (cd functions && npx tsc --noEmit)
```
Expected: оба без ошибок.

- [ ] **Step 6: РУЧНОЙ ШАГ — деплой на iPhone**

Инструкция пользователю (выполняется вместе):
1. Xcode → Settings → Accounts → Add Apple ID (бесплатный). Скопировать Team ID личной команды → вписать в `ios/Config/Local.xcconfig`: `DEV_TEAM = <TeamID>`; `cd ios && xcodegen`.
2. iPhone подключить кабелем, разблокировать, «Доверять этому компьютеру».
3. На iPhone включить Developer Mode: Настройки → Конфиденциальность и безопасность → Режим разработчика (появляется после первой попытки установки).
4. `open ios/SmartGolfCaddy.xcodeproj` → выбрать устройство → Run (⌘R). Первый раз Xcode создаст сертификат и профиль сам.
5. На iPhone: Настройки → Основные → VPN и управление устройством → доверять профилю разработчика.
6. В приложении: войти через Google, нажать «Проверить связь с сервером» — и зарегистрировать debug token УСТРОЙСТВА (он свой на каждой инсталляции) как в Step 3.

Expected: приложение работает на iPhone, вход + диагностика зелёные.

- [ ] **Step 7: Commit**

```bash
git add ios/SmartGolfCaddy/Services/CallableContracts.swift ios/SmartGolfCaddy/Views/DiagnosticsView.swift ios/SmartGolfCaddy/Views/HomePlaceholderView.swift src/types/callable.ts functions/src/contracts.ts
git commit -m "feat(ios): callable contracts + App Check smoke diagnostics, on-device run"
```

---

### Task 8: Документация

**Files:**
- Modify: `SETUP.md` (секция iOS)
- Modify: `CLAUDE.md` (команды и архитектура iOS)

**Interfaces:**
- Consumes: фактическое состояние после Tasks 1–7.
- Produces: онбординг iOS-разработки для будущих сессий.

- [ ] **Step 1: Добавить секцию в SETUP.md**

Дописать в конец `SETUP.md` (через `cat >> SETUP.md << 'EOF' … EOF`):

```markdown
## iOS-приложение (ios/)

Требования: полный Xcode (App Store), `brew install xcodegen`.

1. `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
2. `cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig`
3. GoogleService-Info.plist (не в git): Firebase console → Project
   settings → Your apps → iOS «Smart Golf Caddy iOS» → скачать в
   `ios/SmartGolfCaddy/Resources/`. REVERSED_CLIENT_ID из него → в
   Local.xcconfig (GOOGLE_REVERSED_CLIENT_ID).
4. `cd ios && xcodegen` — сгенерировать .xcodeproj (после каждой
   правки project.yml).
5. App Check: приложение в Debug печатает "App Check debug token" в
   консоль. Зарегистрировать: Firebase console → App Check → Apps →
   iOS-app → Manage debug tokens. Без этого callable отвечают
   unauthenticated. Токен уникален per-инсталляция.
6. Запуск на iPhone: Apple ID в Xcode → Accounts, Team ID → в
   Local.xcconfig (DEV_TEAM), устройство в Developer Mode, Run из
   Xcode. Бесплатная подпись живёт 7 дней, потом Run заново.
```

- [ ] **Step 2: Добавить в CLAUDE.md**

В `CLAUDE.md`, в конец секции «Common commands», дописать:

```markdown
iOS (нативное приложение, `ios/`):

```bash
export SIM_NAME="iPhone 17"        # или из: xcrun simctl list devices available
cd ios && xcodegen                 # регенерация .xcodeproj после правки project.yml
xcodebuild -project SmartGolfCaddy.xcodeproj -scheme SmartGolfCaddy \
  -destination "platform=iOS Simulator,name=$SIM_NAME" -derivedDataPath "$DD" test
```

iOS-архитектура зеркалит веб: Views → ViewModels (@Observable) →
Services → Firebase SDK; Models — чистые структуры. `import Firebase*`
только в `Services/` (+ AppDelegate, RootView.onOpenURL, DEBUG-only
DiagnosticsView). Контракты callable: `Services/CallableContracts.swift`
синхронизируется с `functions/src/contracts.ts` (SYNC-маркеры).
ВАЖНО: DerivedData — только вне iCloud (`$DD` выше): артефакты в
~/Documents портит iCloud File Provider → codesign «detritus» fail.
```

- [ ] **Step 3: Commit**

```bash
git add SETUP.md CLAUDE.md
git commit -m "docs: iOS onboarding — setup, commands, architecture notes"
```
