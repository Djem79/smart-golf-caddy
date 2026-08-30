# Tasks — Sprint 8 (P1 batched from audit)

Source: 2026-05-19 multi-agent audit, P1 findings. Sprint 7 already
shipped the 4 P0 fixes; this sprint closes 9 of the highest-impact P1s.

## Active

- [ ] **1. `scoreColor` contrast fix + non-color cue**
  - `types/index.ts:scoreColor` — `#4CAF50` (birdie) → `#2E7D32`
    (contrast 4.6:1 with `#1A1C1C` text, passes WCAG AA).
  - Optional: also darken `#FF9800` (bogey) → `#EF6C00` for symmetry.
  - Add `scoreDirection(diff)` returning `'under' | 'par' | 'over'` for
    a non-color glyph (▼ under, ● par, ▲ over). Use in Leaderboard pill
    + RoundResults table cells.
  - Update `scoreColor.test.ts` for new values.

- [ ] **2. Leaderboard column overflow fix**
  - `screens/Leaderboard.tsx` grid template:
    `28px_1fr_auto_56px_56px` → `36px_1fr_44px_56px` (drop dedicated
    «Удары» column, fold it under name as a secondary line, or move it
    into the diff pill).
  - Verify on 360 px viewport that Russian names like «Александр П.»
    render fully.

- [ ] **3. Modal focus-trap + body-scroll lock**
  - `ShareDialog.tsx`, `ConfirmDialog.tsx`:
    - On open: focus the first interactive element (close button for
      ShareDialog, cancel for ConfirmDialog).
    - On open: `document.body.style.overflow = 'hidden'`; restore on close.
    - Tab cycles within the modal — use a small `useFocusTrap` hook
      OR pin the first/last focusable manually.

- [ ] **4. Non-host Finish: clear UI**
  - `HoleTracker.tsx`: when `round.hostId !== user.uid`, hide the
    «Завершить раунд» button + the «Завершить раунд досрочно» link.
    Show a small subtext «Завершить раунд может только хост».
  - Hosts keep the existing flow.

- [ ] **5. Safe-area on bottom CTAs**
  - `RoundSetup.tsx` action block: `padding-bottom: max(2rem,
    env(safe-area-inset-bottom))`.
  - `HoleTracker.tsx` bottom buttons: same pattern.
  - `JoinGame.tsx`: same.

- [ ] **6. `getUserRounds` paginate / limit**
  - `services/rounds.ts:getUserRounds(userId, limit?)` — default `50`,
    add `orderBy('createdAt', 'desc')` (already there) + `limit(50)`.
  - Home only needs latest 3 — pass `limit: 3` to be explicit.
  - History and Profile use full 50; add a «загрузить ещё» button OR
    just accept 50 cap for now (note in code).

- [ ] **7. Surface errors on data fetches**
  - `screens/Home.tsx`, `Profile.tsx`, `History.tsx`: replace
    `.catch(() => {})` with an `error` state + a small retry banner
    («Не удалось загрузить · Повторить»).
  - Use a tiny shared `useErrorState` hook? No — three call sites is
    not enough for an abstraction. Inline state.

- [ ] **8. MyBag touch targets ≥ 48 px**
  - `MyBag.tsx`:
    - Checkbox (currently w-5 h-5): wrap label in a 48×48 hit area.
    - Delete × button (currently w-6 h-6): make `min-h-touch min-w-touch`.
    - Drag handle (currently w-6 h-10): widen to `min-w-touch`, keep
      visual icon at 16 px centered.

- [ ] **9. Sentry DSN reminder in SETUP.md**
  - Add an explicit «before production launch: set VITE_SENTRY_DSN»
    section.
  - No code changes — Sentry init already handles missing DSN as no-op.

## Verification gate

- `npx tsc --noEmit` (root + functions/) clean
- `npm run lint` clean
- `npm run test:run` — at least 108/108 (added scoreColor tests should
  push us higher)
- `npm run build` succeeds
- Manual:
  - Open Leaderboard with long Russian names → fully visible on 390 px
  - Open ShareDialog → focus lands inside, background doesn't scroll
  - Non-host opens HoleTracker on last hole → no Finish button
  - Profile / Home / History with offline network → see retry banner
  - MyBag: tap exactly on checkbox visual → enables; on the wider hit
    area beside it → also enables (no fat-finger misses)

## Review

_(filled after sprint)_

## iOS — статус и заметки для Фазы 2 (2026-08-18)

Фаза 1 (фундамент) завершена и принята: приложение на iPhone 14 Pro,
вход Google, профиль из Firestore, callable через App Check (debug).
Спека: docs/superpowers/specs/2026-08-17-ios-app-design.md.

Учесть в плане Фазы 2 (из финального ревью фазы 1):
- [ ] subscribeToRound: onError-контракт + экраны РЕНДЕРЯТ ошибку
      (HomePlaceholder сейчас не показывает errorMessage) + отписка в
      deinit per-screen VM (образец SessionViewModel).
- [ ] Конвенция конкурентности колбэков сервисов (@MainActor/@Sendable)
      — решить ДО написания новых сервисов (Swift 6 strict concurrency).
- [ ] Создание раунда: обратная сериализация Round → Firestore,
      per-action rules (LEAVE/START/FINISH), startedAt: null в лобби.
- [ ] Офлайн-очередь: порт transient/permanent семантики shotQueue.ts
      дословно; recordShot идемпотентна; callableDict уже опускает nil.
- [ ] Решение по Dynamic Type (DSFont relativeTo:) — принять до
      первого экрана (ретрофит дорожает).
- [ ] Иконка приложения + Assets.xcassets.
- [ ] Штрафные удары (фича-реквест приёмки 2а): формы — псевдо-клюшка
      «Штраф» в пикере или отдельная кнопка; решить с пользователем
      (влияет на статистику клюшек и веб-паритет).
- [ ] Email deliverability: письма уходят с sandbox-адреса
      onboarding@resend.dev → Gmail кладёт в спам (подтверждено приёмкой
      2а). Настоящий фикс: свой домен в Resend (DNS SPF/DKIM) + заменить
      DEFAULT_FROM в functions/src/index.ts:71. Обход: фильтр в Gmail.
- [ ] Приёмка 2а: проверить ручной ввод названия поля (у пользователя
      раунд получил fallback «Поле для гольфа» — ввод или UX?).
- [ ] CourseSearch: отдельный Places API ключ с iOS bundle-restriction.
- [ ] UpdateHoleConfigInput.par: UI должен ограничивать 3|4|5.
- [ ] Release-сборка без App Check провайдера (#if DEBUG) — для
      TestFlight/App Store нужен App Attest (фаза App Store).
- [ ] Диагностика жжёт join-квоту (30/день/uid) — не злоупотреблять.

## iOS — статус после Фазы 2б (2026-08-18, принята пользователем)

Фазы 1, 2а, 2б завершены: полный одиночный опыт (auth, соло-раунд,
офлайн-удары, штрафы, история, профиль/статистика, сумка, поиск полей,
иконка). Осталась Фаза 3: групповая игра (лобби, join, лидерборд) +
нативные фичи (GPS-дальномер удара, Live Activity, хаптика есть).

Мелочи в Фазу 3 (из финального ревью 2б):
- [ ] lastClubUsed не должен запоминать «Штраф» (предвыбор на след. лунке)
- [ ] «Сменить поле» плодит дубль courseSearch в стеке
- [ ] Итоги из Истории: нет пути назад к списку (back скрыт, домик уводит)
- [ ] Веб: чип «Штраф» (паритет ввода с iOS)
- [ ] Иконка 878KB — прогнать через оптимизатор
- [ ] geo: транзиентные ошибки прячут «Повторить»; ошибки текст-поиска
      выглядят как «нет результатов»
- [ ] ShotQueue online/monitor без синхронизации (bool, риск мал)
- [ ] Профиль: Int()-усечение гандикапа; пересчёт Scoring на рендер


## Беклог из полного аудита приложения (2026-08-18, 6 агентов; 14 дефектов исправлено сразу)

- [ ] Свайп-назад из трекера может открыть протухший экран поиска
      (courseSearch остаётся в стеке под .hole) — проверить жест на
      устройстве; при подтверждении чинить очисткой стека при создании.
- [ ] Клиентский кап/сообщение на 30 ударов в лунке (сервер режет молча).
- [ ] Скоркарта: колонка суммы (∑) на игрока — есть в вебе.
- [ ] «Поделиться результатом» (shareRoundByEmail недостижим из iOS UI) — Ф3.
- [ ] Веб-чип «Штраф» (iOS опережает веб по вводу штрафов).
- [ ] Group-play: дальномер меряет позицию устройства записывающего —
      при host-scores-for-teammate в Ф3 не приписывать хостовые метры
      чужому слоту (гейт targetUid == currentUserId).
- [ ] Geo-denied во время трекинга — молча; показать статус в GPS-строке.
- [ ] Рост файла shot-marks-v1.json не ограничен (чистка по finish раунда).
- [ ] Средняя дальность клюшек в Профиле (avgDistanceMeters есть в движке).
- [ ] iPad multi-scene: GIDSignIn presenter берёт .first сцену.
- [ ] Форма email в PlayerInfo: веб пишет '', iOS опускает ключ — унифицировать.


## Security/privacy-беклог (аудит 2026-08-18; критичное уже исправлено и задеплоено)

Исправлено сразу: list-дамп раундов (утечка email всех игроков), подделка
playerIds при выходе, обход allowlist рассылки через create, email из
токена при join, правка завершённых раундов, security-заголовки.
Тесты правил: 17 (были 14), покрывают все три эксплойта.

Остаётся (не блокирует, но чинить до роста числа пользователей):
- [ ] Приватность: ShotRangefinder.clear() не вызывается — сырые lat/lng
      копятся в shot-marks-v1.json бессрочно; чистить при finish раунда.
- [ ] Приватность: NSLocationWhenInUseUsageDescription упоминает только
      поиск полей — дописать про замер дистанции ударов.
- [ ] Приватность: нет удаления аккаунта/данных и политики
      конфиденциальности; авто-письмо без opt-out.
- [ ] Приватность: полный email в logger.warn/error функций (есть
      redactEmail на happy-path — применить везде).
- [ ] Приватность: Sentry без beforeSend-скрабинга PII.
- [ ] Группа: участники раунда технически читают email друг друга
      (rules отдают документ целиком) — при возврате групповой игры
      рассмотреть вынос email в подколлекцию.
- [ ] Supply-chain: firebase-admin отстаёт на 2 мажора (12 → 14),
      firebase-functions на 1 — плановый апгрейд закроет каскад
      audit-находок (эксплуатируемых путей сейчас нет).
- [ ] Supply-chain: `npm audit fix` для @remix-run/router (open redirect).
- [ ] Хостинг: CSP не добавлен (риск сломать Firebase/Places) — отдельная
      задача с проверкой на превью-канале.
- [ ] iOS: Package.resolved не в git (SPM-версии не запинены между машинами).
- [ ] .gitignore: точные пути вместо glob для xcconfig/plist.
- [ ] Rules: нет валидации типов timestamp и формы holes/players при create.


## Беклог фазы 3b (метки гринов, 2026-08-20)

- [ ] Правила не валидируют диапазон lat/lng внутри карты holes (Rules не
      умеют итерировать map) — компенсировано клиентской проверкой в
      GreensService.saveMark; рассмотреть callable-запись при публичном релизе.
- [ ] Прямая клиентская запись меток минует App Check и bumpDailyQuota
      (в отличие от остальных user-write путей) — hardening перед бетой.
- [ ] Дистанция до грина не обновляется непрерывно при ходьбе (пересчёт при
      снапшоте раунда/меток и при записи удара) — добавить лёгкий таймер.
- [ ] GreenMarkSet.init?(data:) падает целиком при мусорной форме одной лунки
      (нужен per-entry compactMap).
- [ ] Нет тестов правил на форму (лишний ключ, holes не map, >18 лунок).
- [ ] greenRow: проверить вёрстку на узких экранах (iPhone SE) и верхний отступ.


## Фаза 3c (Apple Watch companion) — выполнена (2026-08-24)

План: `.superpowers/sdd/2026-08-20-ios-phase3c-apple-watch/`. 6 задач,
все приняты. Итог: watch-таргет (WKApplication, компаньон), контракт
сообщений `WatchMessages.swift` (v1, NSNumber-устойчивое декодирование),
мосты `WatchBridge`/`PhoneBridge`, экран лунки на часах (счётчик ударов,
пикер клюшек), durable-очередь ударов с квитанциями и идемпотентностью
по `sequence`, дистанция до грина по GPS часов. Пороги GPS сведены в
`GeoGates` (Models/Geo.swift) — единая точка для телефона и часов.
Финальное живое ревью фазы (диапазон `10fe09f..7c9b611`) прошло пять
раундов правок одной и той же границы "confirmedCount vs myShots vs
локальный кэш часов" (Fix 2 → Fix 7 → Fix 9), каждый раз латая один край
и открывая соседний. Пятый раунд заменил границу МОДЕЛЬЮ: убрал
`WatchRoundViewModel.shotsByHole`/`confirmedCount` целиком —
`WatchRoundViewModel` больше не хранит клюшки в памяти и не сводит
`myShots` с локальным состоянием часов в одно число. Вместо этого две
непересекающиеся ПО ПОСТРОЕНИЮ величины читаются живьём при каждом
обращении: `snapshot.myShots` (сервер) и `WatchShotQueue.pending`
(локальный durable-хвост, единственный источник "что часы ввели, а
телефон ещё не принял"); счёт на экране — их сумма. Рехидратация после
выгрузки процесса часов перестала быть отдельной механикой — читать
больше нечего кэшировать. Осознанный компромисс (временное завышение
счёта в узком окне между записью на сервере и приходом квитанции)
задокументирован в CLAUDE.md и коде. Идемпотентность по `sequence` +
`installId` (Fix 5/8) не тронута этим рефакторингом. Инварианты — в
CLAUDE.md, раздел "Фаза 3c". Тесты (прогнаны дважды подряд для проверки
стабильности): iOS 178/178, watchOS 75/75. Полный отчёт финальной
задачи — `.superpowers/sdd/2026-08-20-ios-phase3c-apple-watch/task-6-report.md`,
разбор корневой причины и рефакторинга — `task-4-report.md` в той же
папке.

### Review

Сквозной прогон на спаренных симуляторах доказал снимок телефон→часы
живьём (реальные пар/дистанция/название поля отразились на часах после
создания раунда на телефоне). Доставку батча ударов часы→телефон
(`transferUserInfo`) подтвердить в симуляторе НЕ удалось несмотря на две
разные честные попытки (живое ожидание при `reachable: YES` + нудж через
реактивацию `WCSession` релончем телефона) — на watch-стороне `transferUserInfo:`
подтверждённо вызывается и принимается локальным демоном
(`transferring: YES`), но соответствующего приёма на телефоне
(`WatchBridge.session(_:didReceiveUserInfo:)` / изменение `round.holes`
на сервере) зафиксировать не получилось. Это совпадает с находкой Task 4
(«известная ненадёжность transferUserInfo в watchOS Simulator») — не
код-дефект (отправляющая сторона по логам работает штатно), но и не
закрытый вопрос: **реальное подтверждение доставки батча остаётся за
проверкой на физических часах** (см. беклог ниже и SETUP.md).

### Беклог фазы 3c

- [ ] Расширить `HoleTrackerViewModelTests` на `sendWatchSnapshot` и
      выбор ударов по `myShots`/`activeUserId` (покрытие снимка,
      уходящего на часы, тестами не закрыто).
- [ ] Ограничение «снимок телефон→часы уходит только при открытом экране
      лунки» (`HoleTrackerViewModel.sendWatchSnapshot`) — кандидат на
      улучшение: телефон в кармане с закрытым экраном — основной сценарий
      игры с часов, снимок в этом случае не обновляется до следующего
      открытия экрана на телефоне.
- [ ] Доставка батча ударов часы→телефон НЕ подтверждена вживую (только
      в симуляторе — см. Review выше); первое, что проверить на реальном
      железе (протокол — в SETUP.md, раздел «Apple Watch companion»).
- [ ] Устойчивость durable-хвоста (`WatchShotQueue.pending`) к выгрузке
      процесса часов и защита от sequence-коллизии при переустановке
      через `installId` (Fix 8) — обе закрыты юнит-тестами (трассировки
      воспроизведены в `WatchRoundViewModelTests`/`WatchBridgeTests`/
      `WatchBatchSequenceLedgerTests`), но НЕ подтверждены на реальном
      устройстве: нужен сценарий "выгрузить приложение часов из памяти
      (или force-quit) с неподтверждённым ударом в очереди, дождаться
      квитанции, добавить новый удар" и отдельно "удалить и
      переустановить приложение часов посреди раунда, ударить" — тот же
      протокол реального железа, что и пункт выше.
- [ ] Параллельный ввод ударов с телефона и часов на одной лунке
      (протокол — SETUP.md, «Apple Watch companion») — не требует
      force-quit/переустановки, воспроизводится в обычной игре легче
      прочих сценариев из этого списка; проверяет живьём осознанный
      компромисс временного завышения счёта на часах (см. CLAUDE.md).
- [ ] Завершить раунд с недоставленным ударом на часах (Fix 12, живое
      ревью Task 4) — на симуляторе не проверено вживую (transferUserInfo
      ненадёжен в watchOS Simulator, см. Review выше), на устройстве это
      НЕ гипотетика: ударить на часах вне связи с телефоном → завершить
      раунд на телефоне → вернуть связь → убедиться, что баннер "удар не
      сохранён — раунд уже завершён" появляется на часах (не тихая
      потеря) и слот в WatchShotQueue.pending срезается.
- [ ] Баннер об отклонённом ударе на часах хранится в одиночном состоянии:
      два подряд завершённых раунда с недоставленными ударами — сообщение о
      более раннем перезапишется. Нужна очередь сообщений, а не одно.
- [ ] Серверное grace-окно для `recordShot` в недавно завершённый раунд
      (обсуждалось при разборе Fix 12, НЕ реализовано намеренно —
      контроллер попросил не трогать без отдельного решения владельца).
      Идея: `functions/src/index.ts:273` вместо жёсткого отказа для
      `status !== 'active'` мог бы разрешать запись в короткое окно
      (например, 2–5 минут) после `finishedAt`, закрывая сценарий Fix 12
      на сервере, а не только UI-сигналом на часах. Компромиссы: (а) это
      правка контракта `recordShot` — требует передеплоя functions и
      согласования; (б) окно должно быть достаточно коротким, чтобы не
      противоречить ожиданию "финальный счёт неизменен после завершения"
      (RoundResults уже мог уйти игроку по email); (в) потребует решить,
      пересчитывать ли totalScore/scoreDiff `finished`-раунда постфактум,
      если удар всё же дописался. Оценка: небольшая (1 файл,
      `functions/src/index.ts`, + `firestore.rules` не меняется —
      `players`/`holes` уже server-only), но требует явного решения
      владельца продукта, не инженерное решение в одиночку.

## Фаза 3d-1 — удаление аккаунта (требование App Store 5.1.1(v))

Решение владельца: в групповых раундах участие ОБЕЗЛИЧИВАЕТСЯ (счёт
остаётся товарищам, имя/аватар/email стираются), соло-раунды удаляются
целиком.

Что удаляет callable `deleteAccount` (Admin SDK, enforceAppCheck):
- [x] `users/{uid}` — профиль целиком
- [x] `userQuota/{uid}` — счётчики квот
- [x] `courses/*/greenMarks/{uid}` — метки гринов (привязаны к uid)
- [x] соло-раунды (`playerIds == [uid]`) — целиком
- [x] групповые раунды — `players[uid]` → имя «Удалённый игрок», avatar
      и email стираются; `playerIds` и удары ОСТАЮТСЯ (иначе поедет
      match-результат и таблица товарищей)
- [x] Firebase Auth — запись удаляется ПОСЛЕДНЕЙ (если упадём раньше,
      пользователь сможет повторить; обратный порядок оставил бы
      осиротевшие данные без владельца)

Задачи:
- [x] T1: `functions/src/index.ts` + `contracts.ts`, зеркала контракта в
      `src/types/callable.ts` и `ios/.../CallableContracts.swift` (SYNC)
- [x] T2: веб — кнопка в Profile + ConfirmDialog + сервис
- [x] T3: iOS — ProfileView + сервис
- [x] T4: доки (CLAUDE.md, SETUP.md)
- [ ] Деплой `deleteAccount` в прод (`firebase deploy --only functions`)

РЕШЕНО (ревью T1): роль хоста передаётся первому из оставшихся игроков,
`status` не трогается. Первая версия принудительно завершала раунд — это
теряло неотправленный удар соигрока (`failed-precondition` считается
окончательным отказом и в вебе, и на iOS) и рассылало всем письма об
«итогах» ещё идущей игры. Логика вынесена в `deleteAccountDecision.ts`
и покрыта тестами.

Решение (T1, после ревью): force-finish раунда отклонён — ломает третьих
лиц (`onRoundFinished` шлёт email ВСЕМ playerIds на любой флип в
`finished`, включая программный, с промежуточным счётом + жжёт их
дневную квоту; `recordShot` после этого перманентно отклоняет ещё не
доставленные удары соигроков из офлайн-очереди — веб/iOS дропают их без
возможности повторить). Вместо этого при удалении хоста lobby/active
раунда роль хоста передаётся первому оставшемуся участнику
(`playerIds`), `status` не трогается ни в одной ветке. Чистая логика
решения вынесена в `functions/src/deleteAccountDecision.ts`
(`decideRoundDeletion`) и покрыта юнит-тестами
(`functions/src/deleteAccountDecision.test.ts`, свой `vitest` в
`functions/` — отдельный TS-проект, гоняется `cd functions && npm run
test:run`).

### Беклог фазы 3d-1

- [x] `deleteAccount` шаг 3 (`courses/*/greenMarks/{uid}`) читает ВСЕ
      метки гринов ВСЕХ пользователей на каждое удаление аккаунта
      (`collectionGroup('greenMarks').get()` + фильтр по doc.id в коде —
      обоснование в `functions/src/index.ts`). Стоимость растёт с
      объёмом системы, а не с данными удаляемого пользователя —
      кандидат на реверс-индекс (например, `users/{uid}/greenMarkRefs`)
      при заметном росте коллекции.

### Бэклог, найденный при ревью фазы 3d-1

- [ ] `ConfirmDialog`: клик по подложке и Escape закрывают диалог даже во
      время `loading` — `onCancel` вызывается безусловно. В потоке удаления
      аккаунта это даёт мёртвую паузу: диалог закрыт, кнопка заблокирована,
      обратной связи нет, пока не ответит сервер. Само себя чинит (успех →
      навигация, ошибка → сообщение), но правильнее блокировать закрытие
      при `loading`. Затронет всех потребителей компонента — к лучшему.
- [ ] `useProfile.ts` вызывает `subscribeToProfile(uid, callback)` БЕЗ
      третьего аргумента `onError`, хотя сигнатура его поддерживает, а
      CLAUDE.md требует передавать всегда (иначе ошибка прав/сети = вечный
      спиннер). Пре-существующий пробел (последняя правка файла — f3953c4,
      задолго до фазы 3d-1), не регрессия. В потоке удаления не стреляет,
      но остаётся реальным долгом.

## Пункт 6 App Store — публичные страницы: ВЫПОЛНЕНО

Задеплоено и проверено на проде (открываются без входа, в обход SPA):
- https://smart-golf-caddy.web.app/privacy
- https://smart-golf-caddy.web.app/terms
- https://smart-golf-caddy.web.app/support

Страницы статические (`public/*.html`), английские, отдаются Firebase
Hosting напрямую — работают, даже если JS-бандл сломан. `cleanUrls: true`
даёт адреса без расширения. Ссылки на них есть в профиле веба и iOS.

Политика покрывает ЯВНЫЙ список Apple 5.1.1(i): какие данные, каким
способом собираются, зачем, кому передаются, сопоставимая защита у
третьих сторон, сроки хранения, удаление, отзыв согласия. Плюс
безопасность и порядок изменений.

Честно раскрыто: резервные копии базы переживают удаление аккаунта —
PITR 7 дней, ежедневные снимки 98 дней.

- [ ] **Юридическая проверка человеком** — тексты составлены как честное
      техническое описание фактического поведения, юристом НЕ проверялись.
      Особенно требуют внимания: соответствие GDPR и 152-ФЗ, раскрытие про
      бэкапы, нейтральная формулировка о применимом праве.
- [ ] Указать эти адреса в App Store Connect (Privacy Policy URL, Support URL)
- [ ] Свой домен вместо `*.web.app` — опционально, на проходимость ревью
      не влияет

## Фаза 4 — локализация: ВЫПОЛНЕНО

Веб, iOS, часы и письма переведены на два языка. Переключатель в профиле,
выбор хранится в `AppUser.locale` и синхронизируется между устройствами.
Механизм и принятые решения — в CLAUDE.md, раздел «Локализация».
Тесты: веб 151, functions 39, iOS 195, часы 83 — всё зелёное.

- [ ] Долг: «Удалённый игрок» пишется сервером по-русски. В письмах
      подменяется переводом, в интерфейсе веба и iOS показывается как
      есть. Чинится переходом на нейтральный маркер в базе + перевод при
      отображении (как сделано для PENALTY_ID), но требует совместимости
      с уже записанными данными.
- [ ] Деплой локализации в прод (hosting + functions)

## Фаза 4б — хвосты локализации (согласовано с владельцем)

### 1. Тексты системных разрешений не переведены
Симптом виден на живом симуляторе: системный диалог просит доступ к
геолокации по-английски, а наше пояснение под ним — по-русски.
Причина: `NSLocationWhenInUseUsageDescription` живёт в Info.plist
(`ios/project.yml`), а не в коде, поэтому наш словарь его не покрывает.
Касается ревью Apple: гайдлайн требует внятного объяснения, зачем доступ.
Решение: `InfoPlist.strings` для `ru` и `en` для ОБОИХ таргетов (телефон
и часы), тексты разные — на телефоне про поиск полей, на часах про
дистанцию до грина и замер ударов.
Проверять фактом: запустить симулятор с английской локалью и убедиться,
что диалог целиком английский.

### 2. «Удалённый игрок» приходит с сервера по-русски
Строку пишет `deleteAccount` при обезличивании участия. В письмах она уже
подменяется переводом при сборке, а в интерфейсе веба и iOS показывается
как есть — англоязычный пользователь видит русскую фразу в таблице.
Решение: хранить в базе нейтральный маркер и переводить при отображении
(как сделано для `PENALTY_ID`/`UNKNOWN_CLUB`).
ОСТОРОЖНО: у существующих обезличенных записей в базе уже лежит русский
литерал — новый код обязан продолжать их отображать корректно.

---

# ТОЧКА ВОЗОБНОВЛЕНИЯ (обновлено 30.08.2026)

Ветка `main`, всё запушено на GitHub, дерево чистое.
Тесты на момент паузы: веб 154, functions 41, iOS (с Apple-входом) 48 в
наборе авторизации, часы 83 — всё зелёное.

## Чек-лист подачи в App Store

| # | Пункт | Статус |
|---|---|---|
| 1 | Платный Apple Developer Program | НЕТ — блокер для пункта 2 |
| 2 | Sign in with Apple | iOS-часть готова (b3b916f), осталось: веб, отзыв токена, включение |
| 3 | Удаление аккаунта | ГОТОВО, в проде |
| 4 | Тексты разрешений | ГОТОВО, переведены (fb557ca) |
| 5 | Платные функции | не применимо |
| 6 | Сайт: privacy/terms/support | ГОТОВО, в проде |

## Следующие задачи (план: docs/superpowers/plans/2026-08-29-sign-in-with-apple.md)

- [ ] T2: веб — провайдер `apple.com`, кнопка по HIG, обработка
      `auth/account-exists-with-different-credential` со сценарием
      связывания аккаунтов
- [ ] T3: `deleteAccount` — отзыв токена Apple
      (`POST https://appleid.apple.com/auth/revoke`, требование TN3194).
      ВАЖНО: наша функция удаления сейчас этого НЕ делает, и без этого
      Apple отклонит приложение, использующее вход через Apple
- [ ] T4: чек-лист «что включить после оплаты» в SETUP.md

## Ловушки, которые нельзя забыть

1. **Скрытая почта Apple** выдаёт адрес `@privaterelay.appleid.com`.
   Письма туда НЕ дойдут, пока домен отправителя не зарегистрирован у
   Apple. Сейчас отправитель — песочница `onboarding@resend.dev`, она не
   подойдёт: нужен свой домен.
2. **Второй аккаунт при скрытой почте.** Если человек входил через Google,
   а потом выберет «скрыть почту» — адреса разные, Firebase создаст второй
   аккаунт. Автоматически не решается, нужен явный сценарий связывания.
3. **Имя от Apple приходит один раз** — при первой авторизации. Уже учтено
   в iOS-коде, не сломать при доработках.

## На стороне владельца

- [ ] Оплатить Apple Developer Program ($99/год) — разблокирует пункт 2
- [ ] Юридическая проверка текстов privacy/terms человеком (GDPR, 152-ФЗ)
- [ ] Заполнить декларацию приватности в App Store Connect
- [ ] Завести демо-аккаунт для проверяющего (всё приложение за логином)
- [ ] Приёмка часов на поле: запись ударов с запястья, дистанция до грина
