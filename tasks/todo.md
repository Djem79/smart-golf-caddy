# Tasks — Sprint 2 (quality, perf, test coverage)

Source: audit synthesis 2026-05-19 + Sprint 1 review.

## Active

_(no active task — Sprint 2 done)_

## Verification gate

- ✅ `npx tsc --noEmit` clean
- ✅ `npm run test:run` — 89/89 (up from 65 after Sprint 1 dropped duplicate RoundResults.test.tsx)
- ✅ `npm run build` — succeeds; main chunk down from 624 kB to 601 kB (with screens now as separate 2-21 kB lazy chunks)
- ⚠️ `npm run lint` — 7 pre-existing `react-hooks/set-state-in-effect` warnings remain; tracked for Sprint 3

## Review

### What shipped

- [x] **1. Cleanup: `computePlayerTotals` import + dead Zustand fields**
  - `Home.tsx`, `History.tsx` import `computePlayerTotals` directly from
    `services/scoring.ts`; the re-export from `RoundResults.tsx` is gone.
  - `RoundResults.test.tsx` was a duplicate of `scoring.test.ts` —
    deleted; coverage unchanged.
  - `useAppStore` trimmed to only `lastClubUsed`/`setLastClubUsed`.
    Removed `activeRound`, `currentHoleIndex`, and their setters
    (never read anywhere).

- [x] **2. `pluralRu` extracted + sweep**
  - New `src/utils/intl.ts` with the helper. 15 unit tests covering
    teens (11-14), normal forms (1, 2-4, 5+), and 100s edge cases.
  - Inline duplicate in `CourseSearch.tsx` removed.
  - Sweep replacing two-form fallbacks:
    - `GroupLobby.tsx` — игрок/игрока/игроков
    - `Profile.tsx` — удар/удара/ударов
    - `Home.tsx`, `History.tsx`, `RoundResults.tsx` — лунка/лунки/лунок
    - `History.tsx` also fixed игр./игрока/игроков

- [x] **3. Global `*:focus-visible` ring**
  - One rule in `src/styles/index.css` `@layer base` applies a
    2px primary-coloured outline on keyboard focus only.
  - Removed `outline-none` from all 7 input sites — they now inherit
    the global ring without overriding it.

- [x] **4. `React.lazy` on heavy screens**
  - 9 of 11 screens lazy-loaded (everything except Auth + Home).
  - `<Suspense fallback={<LoadingScreen />}>` wraps `<Routes>`.
  - Per-screen chunks: 0.56-21 kB; main went 624 → 601 kB (-23 kB).
  - Main chunk is still dominated by Firebase SDK (needed for auth
    state at mount). Splitting Firebase out requires lazy-loading
    auth — deferred (acceptable: 185 kB gzipped initial).

- [x] **5. Tests for `joinRoundByCode` and `recordShot`**
  - 9 new tests in `services/rounds.test.ts` (now 16 total):
    - join: empty code → null; no match → null; match → roundId +
      correct write payload (`players.{uid}` + `playerIds: arrayUnion`)
    - recordShot: round doesn't exist; status !== 'active'; user not
      in playerIds; holeIndex out of range; happy path writes correct
      holes structure (only target hole modified, payload shape matches).
  - Extended the firebase/firestore mock with `runTransaction`,
    `arrayUnion`, `arrayRemove`, `Timestamp` class.

### Bonus fix

- `RoundSetup.tsx`: removed `Date.now()` from render body (was creating
  a new synthetic course id on every keystroke). Moved into `handleStart`.

### Lint warnings deferred to Sprint 3

7 errors of kind `react-hooks/set-state-in-effect` in:
- `hooks/useGeolocation.ts` (3) — setState in initial-mount effect
- `hooks/useAuth.ts`, `hooks/useProfile.ts` (1 each) — onAuthStateChanged callback setState
- `screens/HoleTracker.tsx` (1) — selectedClub auto-snap effect
- `screens/MyBag.tsx` (1) — sync from server profile snapshot effect

These are React 19 best-practice warnings, not runtime bugs. Fixes
typically require either lifting state to event handlers, using
`useSyncExternalStore`, or refactoring effects to one-shot setup +
callbacks. Out of Sprint 2's quality-of-life scope.

### Not done (intentionally deferred)

- Lint sweep on `set-state-in-effect` warnings (Sprint 3 candidate)
- Cloud Function proxy for Google Places API (Sprint 3)
- Sentry monitoring (Sprint 3)
- vite-plugin-pwa / service worker (Sprint 3)
- README rewrite + SETUP.md group-play update (Sprint 3)
- CI workflow (Sprint 3)
