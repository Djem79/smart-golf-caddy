# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Smart Golf Caddy — mobile-first React PWA для трекинга гольф-раундов
(русский UI). Target viewport — **390 px wide** (`.screen` утилита
форсит `max-w-[390px] mx-auto`).

**Stack:**
- Frontend: React 19 + TypeScript + Vite + Tailwind 3 + Zustand
- Backend: Firebase 10 (Auth + Firestore + Hosting) + Cloud Functions
  Gen 2 (Node 20, `functions/`)
- Email: Resend + `react-email` (rendered server-side в functions)
- PWA: `vite-plugin-pwa`, Sentry: `@sentry/react`
- Tests: Vitest + @testing-library + jsdom

**Design system:** Fairway Elite — green primary `#00450D` /
primary-container `#1B5E20`. **Шрифт унифицирован: Playfair Display**
(весь UI, headlines и body — один шрифт, см. Sprint 8). Иконки —
**lucide-react** (никаких эмодзи). Все токены в `tailwind.config.js`.

Сейчас в проде версия **v1.0.0** (см. git tag, GitHub Release,
`BACKUP.md`).

## Common commands

```bash
# Node через nvm — в свежей сессии нужно `source ~/.nvm/nvm.sh`
npm run dev              # Vite dev server :5173
npm run build            # tsc -b && vite build
npm run test             # vitest watch
npm run test:run         # vitest run (CI mode)
npm run test:run -- src/services/scoring.test.ts   # одиночный файл
npm run lint             # eslint .
npx tsc --noEmit         # type-check (без emit)
```

Functions (отдельный TypeScript-проект в `functions/`):

```bash
cd functions
npm run build            # tsc
npx tsc --noEmit         # type-check functions без emit
npm run email:dev        # react-email dev preview :3000
```

Firebase CLI (auth через `firebase login` уже сделан):

```bash
source ~/.nvm/nvm.sh
firebase deploy --only hosting             # frontend
firebase deploy --only functions           # cloud functions
firebase deploy --only firestore           # rules + indexes
firebase deploy --only firestore,functions,hosting   # всё сразу
firebase functions:log                     # tail логов всех функций
firebase functions:secrets:set RESEND_API_KEY   # ротация секрета
firebase functions:list                    # список развёрнутых функций
```

Setup-инструкции для `.env.local`, Auth provider, Places API и Resend —
в `SETUP.md`. Бэкап / recovery — в `BACKUP.md`.

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
- `functions/` — отдельный TypeScript-проект со своим `package.json`
  и `tsconfig.json`. Хранит email-шаблоны и Cloud Functions.
  При работе с functions всегда `cd functions` для команд.

### Cloud Functions (Sprint 6+7)

Все Cloud Functions в `us-central1` (Firestore в `europe-west3` —
cross-region warning подавляется, см. `firebase.json`). Список
функций:

| Function | Триггер | Что делает |
|---|---|---|
| `onRoundFinished` | `firestore.document('rounds/{id}').onUpdate` | Auto-email при `status: active → finished`. Atomic lease + per-uid tracking (`emailingStartedAt`, `emailedTo`, `emailedAt`) — см. inline комментарии в `functions/src/index.ts`. |
| `recordShot` | callable | Server-authoritative запись ударов. Закрывает cross-player griefing. Клиентский transaction УБРАН. |
| `joinLobbyByCode` | callable | Server-side lookup лобби. Клиент НЕ читает рунд напрямую — `allow get` требует participation. |
| `updateHoleConfig` | callable | Host-only edit par + distanceMeters для лунки. |
| `shareRoundByEmail` | callable | Manual share. Recipient-allowlist (только участники + caller's auth email), daily quota 10/uid в `userQuota/{uid}`. |

Secrets через `defineSecret('RESEND_API_KEY')`. Ротация: `firebase
functions:secrets:set RESEND_API_KEY` + redeploy.

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
- `PlayerInfo.email?` — добавлен в Sprint 6 для post-round email
  rollup. Старые раунды без email отрабатываются через Auth lookup.
- `Round.playMode?: 'stroke' | 'match'` — Sprint 4. Match play
  работает только для `playerIds.length === 2`.
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
- **`useAppStore` (Zustand)** хранит только `lastClubUsed`.
- **Optimistic UI** в `HoleTracker`: `localClubs` маскирует server
  snapshot до `lastSyncedKeyRef.current === serverKey`. Reset на
  смене лунки, игрока, или ошибке сохранения.

### Group play & concurrency

`recordShot` теперь **callable Cloud Function** (Sprint 7). Клиент
больше НЕ делает `runTransaction` напрямую — все записи в `holes`
запрещены `firestore.rules` на уровне rules-engine. Сервер enforces
`request.auth.uid` matching slot. Аналогично `joinRoundByCode` —
callable, не клиентский `updateDoc`.

`RoundStatus`: `'lobby' | 'active' | 'finished'`. Solo раунды
скипают lobby. `GroupLobby` и `HoleTracker` подписываются на status
и auto-navigate при flip.

### Firestore security

`firestore.rules` ужесточён в Sprint 7 — больше **НЕ field-permissive**:

- `allow get` на rounds требует `auth.uid in resource.data.playerIds`
  (никаких lobby-bypass — закрыта PII-leak).
- Updates split per-action: JOIN / LEAVE / START / FINISH (RECORD
  SHOT убран — теперь callable).
- `holes`, `emailedAt`, `emailingStartedAt`, `emailedTo`,
  `emailResults` — server-only (rules блокируют client writes).
- `users/{uid}` — owner-only.
- `userQuota/{uid}` — Admin SDK only (clients не имеют доступа).

При изменении rules — обязательно тестировать в emulator перед
`firebase deploy --only firestore`.

### Email (Sprint 6)

Email-шаблон в `functions/src/emails/RoundSummary.tsx` —
react-email компоненты. Payload собирается `buildPayload.ts`. Цвета
pill'ов в `functions/src/emails/types.ts` (дублируют `scoreColor`
в web — keep в sync). При изменении club abbreviations в
`src/types/index.ts:CLUB_ABBREV` — синхронизировать с
`functions/src/emails/buildPayload.ts:CLUB_ABBREV`.

Preview шаблона: `cd functions && npm run email:dev` (Storyboard
на :3000).

### Routing

`src/App.tsx` — все routes. Тяжёлые экраны лениво грузятся через
`React.lazy` (HoleTracker, RoundResults, MyBag, GroupLobby,
Leaderboard). Non-`/auth` routes обёрнуты в `<ProtectedRoute>`
которая редиректит на `/auth` без user. Catch-all `*` → `/home`.
Deep-link `/join/:code` auto-присоединяется по code.

### Testing

Vitest + jsdom + @testing-library/react. Tests рядом с source
(`Foo.test.ts(x)` next to `Foo.ts(x)`).

При импорте модуля, transitively пулящего `firebase/*`, **мокать
Firebase ДО импорта**:

```ts
vi.mock('../firebase', () => ({ db: {}, app: {} }))
vi.mock('firebase/firestore', () => ({...}))
vi.mock('firebase/functions', () => ({
  getFunctions: vi.fn(() => ({ __functions: true })),
  httpsCallable: (_fns, name) => async (payload) => {
    callableCalls.push({ name, payload })
    return { data: callableResponses.get(name) ?? { ok: true } }
  },
}))
```

Стандартный паттерн — в `src/services/rounds.test.ts`. Strict TS
требует, чтобы тестовые фикстуры включали `playerIds` и все
required-поля `Round` типа.

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
- **`scoreColor(delta)`** + non-color cue `scoreDirection(delta)`
  (`TrendingDown | Minus | TrendingUp`) для color-blind users.
- **WCAG AA** color contrast — `scoreColor` values тщательно
  подобраны (`#2E7D32` для birdie, `#EF6C00` для bogey, `#C62828`
  для double+). Не возвращать к ярким Material defaults.

## Things to be aware of

- **CourseSearch** вызывает Places API **из браузера** с
  `VITE_GOOGLE_PLACES_API_KEY` в bundle. Защищён HTTP-referrer +
  API restriction. Cloud Function proxy в roadmap.
- **Sentry** wired (`@sentry/react`) — no-op без `VITE_SENTRY_DSN`.
  ErrorBoundary в `src/components/ErrorBoundary.tsx`.
- **PWA** через `vite-plugin-pwa` — есть offline-friendly precache
  (sw.js + workbox-XXXX.js).
- **Bundle** main chunk ~610 kB (gzip ~188 kB). React.lazy уже
  применён на тяжёлых экранах.
- **Backup** — git tag v1.0.0 + GitHub Release + Firestore PITR
  (7 дней) + daily snapshots (98 дней). См. `BACKUP.md`.
- **Functions secrets** в GCP Secret Manager — `RESEND_API_KEY`
  ротируется через `firebase functions:secrets:set RESEND_API_KEY`
  + redeploy. Старые версии остаются disabled (можно re-enable).
- README.md — stock Vite template; SETUP.md — реальная onboarding.
- `tasks/lessons.md` накапливает паттерны из user-corrections —
  читать в начале сессии.
