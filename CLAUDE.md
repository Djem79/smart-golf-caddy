# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Специфика подгружается по месту работы: `ios/CLAUDE.md` (iOS + Apple
Watch), `functions/CLAUDE.md` (Cloud Functions, контракты, email).

## Project

Smart Golf Caddy — mobile-first React PWA для трекинга гольф-раундов
(русский UI) плюс нативное iOS-приложение с компаньоном для Apple Watch.
Target viewport — **390 px wide** (`.screen` утилита форсит
`max-w-[390px] mx-auto`).

Стек — в `package.json` / `functions/package.json`. Неочевидное: тесты
правил Firestore гоняются в эмуляторе, письма рендерятся server-side в
functions, PWA через `vite-plugin-pwa`.

**Design system:** Fairway Elite — green primary `#00450D` /
primary-container `#1B5E20`. **Шрифт унифицирован: Playfair Display**
(весь UI, headlines и body — один шрифт). Иконки — **lucide-react**
(никаких эмодзи). Все токены в `tailwind.config.js`.

Сейчас в проде версия **v1.0.0** (см. git tag, GitHub Release,
`BACKUP.md`).

## Common commands

Скрипты — в `package.json`; ниже только то, что из него не следует.

```bash
source ~/.nvm/nvm.sh     # Node через nvm — нужно в каждой свежей сессии
npm run test:run -- src/services/scoring.test.ts   # одиночный файл
npm run test:rules       # эмулятор Firestore, нужен JDK 21+ в PATH
npm run test:e2e         # Playwright; требует предварительного npm run build
```

`npm run test:rules` гоняет `firestore.rules.test.mjs` через `firebase
emulators:exec --only firestore` — нужен **JDK 21+ в PATH** (firebase-tools
дропнул JDK <21 в late-2025; на macOS — openjdk через brew, keg-only:
`export PATH="/usr/local/opt/openjdk/bin:$PATH"`).

Деплой — `firebase deploy --only hosting|functions|firestore` (auth через
`firebase login` уже сделан). Setup-инструкции для `.env.local`, Auth
provider, Places API, Resend и установки на реальные устройства — в
`SETUP.md`. Бэкап / recovery — в `BACKUP.md`.

## Workflow orchestration

### 1. Plan-first by default

- Любая задача в 3+ шага или с архитектурой — через письменный план.
- Если что-то пошло не так — **stop and re-plan**, не молотить.
- Плана покрывают и verification, не только build.

### 2. Subagent strategy

- Спавнить сабагентов щедро для разведки / параллельного анализа
  (4-way audit architecture/security/UX/prod-readiness — это модель).
- Тяжёлые задачи → больше compute через параллельных сабагентов.
- **Одна задача на сабагента** — это хранится в
  `memory/feedback_one_task_at_a_time.md`. При plan execution
  диспатчить по одному таску, ждать обоих review перед следующим.

### 3. Self-improvement loop

- После **любой** user correction — добавить паттерн в
  `tasks/lessons.md` (создать если нет).
- Формулировать lesson как правило, предотвращающее повтор.

### 4. Verify before "done"

- Не маркировать таск как complete без доказательства: тесты,
  логи, демонстрация поведения.
- Спросить: «would a staff engineer approve this?» до отправки.

### 5. Demand elegance (in moderation)

- На нетривиальных правках паузить и спросить: «is there a more
  elegant path?» Пропускать для тривиальных фиксов.

### 6. Autonomous bug fixing

- Багрепорт? Просто фиксить. Не держать пользователя за руку.

## Task management

1. **Plan first**: чек-лист в `tasks/todo.md`.
2. **Validate plan**: перечитать перед стартом.
3. **Track progress**: тикать пункты.
4. **Document**: добавить review-секцию в `tasks/todo.md` по окончанию.
5. **Capture lessons**: обновить `tasks/lessons.md` после корректировок.

`TodoWrite` — эфемерный progress (in-session), `tasks/todo.md` —
персистентный между сессиями.

## Operating principles

- **Simplicity first** — минимальный код побеждает.
- **No laziness** — root cause, не band-aid. Senior-engineer стандарт.
- **Minimal blast radius** — трогать только нужное, без drive-by.

## Architecture

### Layers (one-way arrows)

```
screens/  → hooks/ + store/ + services/ + components/
hooks/    → services/
services/ → firebase.ts (only) + Cloud Functions callables
functions/ ← независимый TS-проект, импортит firebase-admin
types/    ← импортит каждый, никаких inbound deps
```

- `services/` — **единственный** слой, импортящий `firebase/*` И
  `firebase/functions`. Тесты мокают этот boundary.

### Data model — central source of truth

`src/types/index.ts` — **каноничная схема** для всего в Firestore.
Некоторые поля имеют legacy-версии — всегда юзать хелперы:

- `HoleShots.clubs: string[]` каноничный. `HoleShots.club?` — legacy.
  Читать через `getHoleClubs(shots)`.
- `AppUser.bag: BagClub[]` каноничный. `AppUser.clubs?` — legacy.
  Читать через `getBagFromUser(user)`.
- `Round.playerIds: string[]` — denormalised membership array
  (нужен для `array-contains` query). Всегда поддерживается рядом с
  `Round.players: Record<uid, PlayerInfo>` map.
- `BagClub.category?` бэкфиллится `getClubCategory(club)` из id.
- `PlayerInfo.email?` — для post-round email rollup. Старые раунды без
  email отрабатываются через Auth lookup.
- `Round.playMode?: 'stroke' | 'match'` — match play работает только для
  `playerIds.length === 2`.
- `Round.emailedAt`, `Round.emailedTo`, `Round.emailingStartedAt`,
  `Round.emailResults` — server-only поля, клиент НЕ пишет (rules
  блокируют).

`DEFAULT_BAG` — это **палитра 20 опций** (не строго 14). USGA-лимит
14 enforced на UI-уровне в MyBag (`TOTAL_SLOTS = 14`).

`normalizeRound(id, data)` в `services/rounds.ts` конвертирует
Firestore `Timestamp` → JS `Date` на границе. `getDoc`-derived
Round объекты ВСЕГДА через `normalizeRound`.

### State management

- **Firestore — source of truth** для раундов и профилей. Screens
  подписываются через `subscribeToRound` / `subscribeToProfile`.
  Обе подписки принимают **третий arg `onError`** — обязательно
  передавать, иначе ошибка прав/сети = вечный спиннер. Экран должен
  показать ошибку + escape (см. GroupLobby/HoleTracker/Leaderboard/
  RoundResults — все 4 передают onError).
- **`useAppStore` (Zustand)** хранит только `lastClubUsed`.
- **Optimistic UI** в `HoleTracker`: overlay `optimistic` тегирован
  слотом `${holeIndex}:${activeUserId}` + `awaitingKey` (= ожидаемый
  serverKey). Дисплей **деривится** (не чистится эффектом): показывает
  optimistic пока он «впереди» сервера; иначе offline-очередь
  (`getPendingShot`); иначе server. Слот-тег чинит протекание между
  игроками при смене активного игрока mid-save; `awaitingKey` чинит
  мигание счётчика назад при быстрых тапах.

### Offline shot queue

`services/shotQueue.ts` — удары записываются через `recordShotQueued`,
а не напрямую через callable. Кладёт в `localStorage` (ключ
`раунд:лунка:игрок`, last-write-wins — безопасно т.к. `recordShot`
идемпотентна), потом пробует синхронизировать:
- Офлайн / транзиентная ошибка → остаётся в очереди (без rollback).
- Перманентный отказ (permission/failed-precondition/...) → дропается
  из очереди + бросает (caller делает rollback + error).
- `flushQueue` гоняется на старте и по событию `window 'online'`
  (`initShotSync` в `main.tsx`).
- HoleTracker мёрджит очередь в дисплей (удары переживают перезапуск)
  и показывает «Нет сети — удары сохранятся автоматически».

Завершение/создание/join раундов в очередь НЕ завёрнуты — требуют
связи (только удары офлайн-устойчивы).

### Group play & concurrency

`recordShot` — **callable Cloud Function**. Клиент НЕ делает
`runTransaction` напрямую — все записи в `holes` запрещены
`firestore.rules`. Модель счёта: **хост ведёт счёт за всех** — callable
принимает `targetUid`, разрешено если `targetUid === caller` ИЛИ
`caller === hostId`. HoleTracker имеет переключатель игроков; запись
идёт через `recordShotQueued(roundId, holeIndex, targetUid, clubs)`.
Аналогично join — callable, не клиентский `updateDoc`.

`RoundStatus`: `'lobby' | 'active' | 'finished'`. Solo раунды
скипают lobby. `GroupLobby` и `HoleTracker` подписываются на status
и auto-navigate при flip.

### Firestore security

`firestore.rules` — **НЕ field-permissive**:

- `allow get` на rounds требует `auth.uid in resource.data.playerIds`
  (никаких lobby-bypass — закрыта PII-leak).
- Updates split per-action: **LEAVE / START / FINISH** (3, не 4).
  Клиентский JOIN убран — join только через callable (Admin SDK),
  поэтому `players` добавлен в server-only blocked keys (закрыта
  PII-forgery: участник мог переписать чужой email).
- `players`, `holes`, `emailedAt`, `emailingStartedAt`, `emailedTo`,
  `emailResults` — server-only (rules блокируют client writes).
- `users/{uid}` — owner-only.
- `userQuota/{uid}` — Admin SDK only (clients не имеют доступа).
- `courses/{courseKey}/greenMarks/{uid}` — читают все аутентифицированные,
  пишет только владелец.

При изменении rules — **обязательно** `npm run test:rules` (эмулятор,
покрывает forgery/leave/start/finish/read-guard) перед `firebase deploy
--only firestore`. Тесты в `firestore.rules.test.mjs`.

### App Check

reCAPTCHA v3, enforced на всех callable. Клиент инициализирует в
`src/firebase.ts`, **no-op без `VITE_APP_CHECK_SITE_KEY`**. Поэтапный
rollout и троттл/ключ-гочи описаны в `SETUP.md`. Ключевое:
- **site key** (`VITE_APP_CHECK_SITE_KEY`) → клиент; **secret** → в
  Firebase console App Check (НЕ перепутать).
- Firebase **browser API key** должен иметь право на «Firebase App
  Check API» (иначе 403 на `exchangeRecaptchaV3Token`).
- Сначала деплой клиента с ключом и проверка verified-запросов, потом
  `enforceAppCheck:true` — иначе все вызовы отвалятся.

### Routing

`src/App.tsx` — все routes. Тяжёлые экраны грузятся через
**`lazyWithReload`** (обёртка над `React.lazy`): при провале dynamic
import (старая вкладка после деплоя → чанк 404) страница один раз
сама перезагружается, чтобы взять свежие чанки (guard в
`sessionStorage` против петли). Non-`/auth` routes обёрнуты в
`<ProtectedRoute>`, которая редиректит на `/auth` без user **и
сохраняет целевой путь** (`state.from`) — Auth возвращает туда после
входа (важно для deep-link `/join/:code`).

### Testing

Tests рядом с source (`Foo.test.ts(x)` next to `Foo.ts(x)`).

При импорте модуля, transitively пулящего `firebase/*`, **мокать
Firebase ДО импорта** — эталон паттерна (включая мок
`firebase/functions` с записью вызовов) в `src/services/rounds.test.ts`,
копировать оттуда. Strict TS требует, чтобы тестовые фикстуры включали
`playerIds` и все required-поля типа `Round`.

**E2E (Playwright)** живут в `e2e/` (исключены из vitest через
`vite.config.ts:test.exclude`). Сейчас — unauth-smoke. Полный
solo-round flow (login → удары → finish) требует Firebase Emulator
Suite — отложен. Vitest и Playwright не конфликтуют — разные
расширения (`*.test.ts` vs `*.spec.ts`) и разные runner'ы.

CI — `.github/workflows/ci.yml`, все джобы обязательны. При падении e2e
`playwright-report/` загружается артефактом на 7 дней.

## Conventions

- **Русский UI** во всех user-facing строках. `pluralRu(n, one, few, many)`
  в `src/utils/intl.ts` — для plurals. Некоторые экраны хардкодят
  два-форменные fallbacks (известный долг).
- **Никаких эмодзи** — только lucide-react иконки (`grep -P
  "[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}]" src/` должен быть пуст).
- **Touch targets ≥ 48 px** через токены `min-h-touch` /
  `min-w-touch`. Не хардкодить `min-h-[48px]`.
- **Numeric inputs в MyBag** используют `defaultValue` + `onBlur`.
- **Firestore writes для user profile** — всегда `setDoc(..., {
  merge: true })`.
- **Модальные диалоги** используют hook `useDialogA11y` +
  `trapTab` (body scroll lock + focus capture/restore + tab cycling).
  См. `ShareDialog`, `ConfirmDialog`, и `HoleEditorDialog` в
  `HoleTracker.tsx`.
- **Buttons** — `Button` компонент с `icon`/`iconRight` для lucide
  иконок. Variant `primary | secondary | ghost`. Full-pill
  (`rounded-full`). Uppercase + `tracking-wider` для CTA-кнопок.
- **Avatar** с fallback на инициалы (`src/components/ui/Avatar.tsx`)
  — НЕ class через img + `?` для пустого src.
- **`scoreColor(delta)`** (фон) + **`scoreOnColor(delta)`** (текст,
  подобран по luminance под каждый фон) — использовать пару, иначе
  контраст не проходит WCAG AA (birdie/double требуют белый текст,
  eagle/par/bogey — тёмный). Плюс non-color cue `scoreDirection(delta)`
  (`TrendingDown | Minus | TrendingUp`) для color-blind users. Не
  возвращать к ярким Material defaults.

## Things to be aware of

- **CourseSearch** вызывает Places API **из браузера** с
  `VITE_GOOGLE_PLACES_API_KEY` в bundle. Защищён HTTP-referrer +
  API restriction. Cloud Function proxy в roadmap.
- **Sentry** wired (`@sentry/react`) — no-op без `VITE_SENTRY_DSN`.
  ErrorBoundary в `src/components/ErrorBoundary.tsx`. `release` =
  `VITE_APP_VERSION`, инжектится в `vite.config.ts` (`<pkg>+<git sha>`).
- **PWA** через `vite-plugin-pwa` (`registerType: 'autoUpdate'`).
  `index.html` отдаётся `no-cache` (firebase.json) для надёжного
  обновления; стейл-чанки ловит `lazyWithReload`.
- **Resume незавершённого раунда**: Home детектит active/lobby раунд и
  показывает карточку «Продолжить» (удары пишутся на сервер сразу, но
  PWA стартует с /home — без этого раунд выглядел «сброшенным»).
- **Bundle** main chunk ~610 kB (gzip ~190 kB). lazy уже на тяжёлых
  экранах.
- **Backup** — git tag v1.0.0 + GitHub Release + Firestore PITR
  (7 дней) + daily snapshots (98 дней). См. `BACKUP.md`.
- README.md — stock Vite template; SETUP.md — реальная onboarding.
- `tasks/lessons.md` накапливает паттерны из user-corrections —
  читать в начале сессии.
