# Smart Golf Caddy — нативное iOS-приложение (SwiftUI)

**Дата:** 2026-08-17
**Статус:** утверждено (дизайн согласован в сессии)
**Связано:** `2026-05-18-smart-golf-caddy-design.md` (веб-версия)

## Цель

Нативная iOS-версия Smart Golf Caddy: полный функциональный паритет с
PWA v1.0.0 плюс нативные фичи, доступные без платного Apple Developer
Program. Тот же Firebase-бэкенд, те же данные — iOS-приложение
становится вторым клиентом существующей системы.

Дистрибуция v1: личный iPhone через бесплатный Apple ID (подпись
обновляется каждые 7 дней). App Store — отдельная будущая фаза.

## Не входит в v1 (отложено)

- **Пуш-уведомления** — APNs требует платный Developer Program.
- **Виджеты и Apple Watch** — после стабилизации ядра.
- **GPS-до-грина** — нет данных о координатах гринов; в модели
  данных лунка знает только `par` и `distanceMeters`.
- **Sign in with Apple** — обязателен при публикации в App Store
  (guideline 4.8, раз есть Google-вход), добавим в фазе App Store.
- **App Attest** для App Check — в v1 используем Debug Provider;
  App Attest потребует платный аккаунт и добавится в фазе App Store.

## Фаза 0 — окружение

Единственный ручной шаг пользователя: установить **Xcode** из Mac App
Store (~15 GB) под своим Apple ID. Всё остальное автоматизируется:

1. `sudo xcode-select -s /Applications/Xcode.app` + приём лицензии
   (`xcodebuild -license accept`).
2. Проверка: `xcodebuild -version`, скачивание iOS-платформы
   (`xcodebuild -downloadPlatform iOS`), запуск симулятора.
3. `brew install xcodegen` — проект описывается декларативным
   `project.yml`; `.xcodeproj` генерируется и НЕ хранится в git
   (нет конфликтов бинарного формата, надёжно для агентной правки).
4. Вход бесплатным Apple ID в Xcode (Settings → Accounts) — ручной
   шаг при первом деплое на устройство; personal team подписывает
   билд на 7 дней.

## Расположение кода

Монорепо, папка `ios/` рядом с `src/` и `functions/`:

```
ios/
  project.yml                 # XcodeGen-манифест
  SmartGolfCaddy/
    App/                      # @main, DI, роутинг
    Models/                   # Codable-структуры (зеркало src/types)
    Services/                 # Firebase boundary (зеркало src/services)
    ViewModels/               # @Observable на экран
    Views/                    # SwiftUI-экраны + компоненты
    DesignSystem/             # цвета, шрифты, размеры
    Resources/                # Assets.xcassets, шрифты, GoogleService-Info.plist
  SmartGolfCaddyTests/        # XCTest
```

Причина монорепо: контракты callable уже синхронизируются маркерами
`SYNC:` между `functions/src/contracts.ts` и `src/types/callable.ts`.
Swift-модели — третья точка синхронизации; в файлах Swift-контрактов
ставится тот же маркер `SYNC:` с указанием обоих парных файлов, и
наоборот — в оба TS-файла добавляется ссылка на Swift-файл.

## Архитектура

Слои зеркалят веб-версию (те же односторонние стрелки):

```
Views (SwiftUI) → ViewModels (@Observable) → Services → Firebase iOS SDK
Models (Codable) ← импортируют все, никаких inbound-зависимостей
```

- **Firebase iOS SDK** через SPM: FirebaseAuth, FirebaseFirestore,
  FirebaseFunctions, FirebaseAppCheck. `Services/` — единственный
  слой, импортирующий Firebase (как в вебе).
- **Auth**: Google Sign-In (GoogleSignIn SDK + FirebaseAuth). Требует
  URL scheme из `GoogleService-Info.plist` (REVERSED_CLIENT_ID).
- **Риалтайм**: `subscribeToRound` / `subscribeToProfile` →
  Firestore snapshot listeners c обязательным error-колбэком
  (правило веба «onError обязателен, иначе вечный спиннер»
  переносится как есть).
- **Callable**: те же 4 функции — `recordShot`, `joinLobbyByCode`,
  `updateHoleConfig`, `shareRoundByEmail` (`us-central1`). Клиент
  никогда не пишет в `holes`/`players` напрямую — rules это блокируют.
- **Timestamps**: конвертация Firestore `Timestamp` → `Date` на
  границе Services (аналог `normalizeRound`).
- **Legacy-поля**: хелперы `getHoleClubs` / `getBagFromUser` /
  `getClubCategory` портируются — старые документы с `club?`/`clubs?`
  должны читаться корректно.

## Офлайн-очередь ударов

Порт семантики `services/shotQueue.ts`:

- Ключ `roundId:holeIndex:targetUid`, last-write-wins (безопасно —
  `recordShot` идемпотентна: пишет весь массив `clubs` лунки).
- Хранение: JSON-файл в Application Support (переживает перезапуск).
- Флаш: при старте приложения и при появлении сети (NWPathMonitor).
- Транзиентная ошибка → удар остаётся в очереди; перманентная
  (permission-denied, failed-precondition…) → дроп из очереди +
  ошибка вызывающему (rollback оптимистичного UI).
- HoleTracker мёрджит очередь в отображение + баннер «Нет сети —
  удары сохранятся автоматически».

Создание/завершение/join раундов в очередь не заворачиваются —
требуют сети (как в вебе).

## App Check (критичная ловушка)

Все callable — `enforceAppCheck: true`. Сейчас в Firebase настроен
только веб-провайдер (reCAPTCHA v3). Без настройки iOS-провайдера
**все вызовы функций с телефона будут отклонены**.

План v1:
1. Зарегистрировать iOS-приложение в Firebase-проекте →
   `GoogleService-Info.plist`.
2. В Debug-сборках — `AppCheckDebugProvider`; debug-токен из логов
   регистрируется в Firebase console.
3. `GoogleService-Info.plist` не коммитится (в `.gitignore`),
   инструкция по получению — в `SETUP.md`.

## Дизайн-система

Порт Fairway Elite в `DesignSystem/`:

- Цвета: primary `#00450D`, primary-container `#1B5E20` и остальные
  токены из `tailwind.config.js` → Asset Catalog.
- Шрифт Playfair Display — бандлится в приложение (OFL-лицензия).
- Иконки — SF Symbols (нативный аналог lucide; эмодзи запрещены).
- Touch targets ≥ 48 pt, русский UI, плюрализация — порт `pluralRu`.
- `scoreColor`/`scoreOnColor`/`scoreDirection` — портируются парой
  + направление (WCAG-контраст и non-color cue, как в вебе).

## Экраны v1 (паритет)

Все 12 экранов веба: Auth, Home (+ «Продолжить раунд»), CourseSearch,
RoundSetup, GroupLobby, HoleTracker (переключение игроков — хост ведёт
счёт за всех; оптимистичный UI со слот-тегами), Leaderboard,
RoundResults, JoinGame (+ deep-link по коду), History, Profile, MyBag
(14 слотов, палитра `DEFAULT_BAG`).

Solo-раунды скипают лобби; `GroupLobby`/`HoleTracker` подписаны на
`status` и авто-навигируют при смене (lobby → active → finished).

CourseSearch: ключ Places API веба защищён HTTP-referrer и на iOS не
работает — нужен отдельный ключ с iOS-bundle-restriction (описать в
SETUP.md).

## Нативные фичи v1 (работают на бесплатном аккаунте)

1. **GPS-дальномер удара** (CoreLocation, when-in-use): кнопка
   «Отметить позицию» у мяча → пройдя к мячу, игрок видит дистанцию
   удара. Не требует координат гринов.
2. **Хаптика** (UIFeedbackGenerator) при записи удара, смене лунки,
   финише раунда.
3. **Live Activity / Dynamic Island**: текущая лунка, счёт, ±par
   во время активного раунда (локальные обновления, без пушей).

## Тестирование

- Порт `scoring.ts` → Swift c XCTest-паритетными тестами (кейсы
  берём из `scoring.test.ts`).
- Codable round-trip тесты на моделях (фикстуры — реальные формы
  Firestore-документов, включая legacy-поля).
- Ручная проверка: симулятор + реальный iPhone (GPS и Live Activity
  проверяются только на устройстве).
- UI-тесты (XCUITest) — отложены.

## Риски

| Риск | Митигация |
|---|---|
| App Check блокирует callable с iOS | Debug Provider с самого начала, проверка первым же интеграционным шагом |
| Расхождение Swift-моделей с Firestore-схемой | SYNC-маркеры + Codable-фикстуры из реальных документов |
| 7-дневная подпись бесплатного Apple ID | Ок для v1; переход на платный аккаунт — без переделок |
| Places API ключ веба не работает на iOS | Отдельный ключ с bundle-restriction, инструкция в SETUP.md |
| Playfair Display лицензия | OFL — бандлить можно |
