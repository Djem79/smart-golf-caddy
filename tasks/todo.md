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
