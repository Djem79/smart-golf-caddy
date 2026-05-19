# Tasks — Sprint 1 (Critical fixes before public users)

Source: audit synthesis on 2026-05-19. Five must-fix items.

## Active

_(no active task — Sprint 1 done)_

## Verification gate (last run before close)

- ✅ `npx tsc --noEmit` — clean
- ✅ `npm run test:run` — 68/68 passing
- ✅ `npm run build` — succeeds (bundle 624 kB, warning about size only)
- ✅ `firebase deploy --only firestore:rules` — deployed successfully

## Review

### What shipped

- [x] **1. Firestore rules — field-aware updates** (`firestore.rules`)
  - Split `allow update` into 5 per-action branches using `affectedKeys()`:
    JOIN / LEAVE / START / FINISH / RECORD SHOT.
  - Each branch enforces immutability of fields it shouldn't touch
    (lobbyCode, hostId, courseId, courseName, totalHoles, holes layout).
  - Added `playerIds.size() <= 8` cap on JOIN.
  - Narrowed `get` to participants OR open lobby; kept `list` permissive
    for joinRoundByCode lookup.
  - Tightened `create` to require host == auth.uid AND playerIds == [hostId]
    AND status ∈ {lobby, active} AND totalHoles ∈ {9, 18}.

- [x] **2. recordShot safety checks** (`services/rounds.ts`)
  - Added inside-transaction validation: status == 'active', user in
    playerIds, holeIndex within range.
  - **Dot-path optimization deferred.** Firestore doesn't support array
    index in dot-paths, so `holes.${i}.shots.${uid}` would only work after
    migrating `holes` from `HoleConfig[]` to `Record<string, HoleConfig>`
    keyed by hole number. That refactor touches types, normalizeRound,
    createRound, all readers, and existing data — out of Sprint 1 scope.
    Lost-update window concern was already handled by runTransaction; the
    remaining cost is bandwidth, which is acceptable at MVP scale.

- [x] **3. normalizeRound preserves `startedAt: null`** (`services/rounds.ts`,
       `types/index.ts`)
  - `startedAt` no longer falls back to `new Date()`; type changed to
    `Date | null` to match the lobby reality.

- [x] **4. ErrorBoundary** (`components/ErrorBoundary.tsx`, `main.tsx`)
  - Class component (React requires this for error boundaries) with
    `getDerivedStateFromError` + `componentDidCatch`.
  - Friendly Russian fallback UI with "Обновить страницу" / "На главную"
    buttons. Dev mode shows the error message in a `<pre>`.
  - Logs to console.error until Sentry lands in Sprint 3.

- [x] **5. Profile + Auth UI cleanup** (`screens/Profile.tsx`, `screens/Auth.tsx`)
  - "(Plan 2)" leak removed from Profile → "Скоро будет доступен" copy.
  - Replaced `🔵 Войти через Google` with the official 4-colour Google G
    SVG mark inline; button is now white with outline + black text +
    brand logo (matches Google brand guidelines for sign-in).

### Lessons captured

See `tasks/lessons.md` — added:
- "When recommending dot-path Firestore updates, check whether the
  target field is an array — Firestore dot-path doesn't index arrays."

### Not done in Sprint 1 (intentionally deferred)

- Dot-path / array → map refactor for `holes` (see Task 2 note above)
- Cloud Function proxy for Google Places API key (Sprint 3)
- Sentry / error monitoring (Sprint 3)
- Code splitting via `React.lazy()` (Sprint 2)
- `pluralRu` extraction + plural-correctness sweep (Sprint 2)
- Global focus-visible styles (Sprint 2)
- Tests for joinRoundByCode / recordShot (Sprint 2)
