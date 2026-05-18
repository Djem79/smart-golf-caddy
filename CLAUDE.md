# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Smart Golf Caddy — mobile-first React PWA for tracking golf rounds (Russian UI). Stack: React 19 + TypeScript + Vite + Tailwind + Firebase 10 (Auth + Firestore) + Zustand + Vitest. Target viewport is **390 px wide** (`.screen` utility enforces `max-w-[390px] mx-auto`). Design system: **Fairway Elite** — green primary `#1B5E20`, Montserrat headlines, Inter body. All tokens live in `tailwind.config.js`.

Original specs and plans live in `docs/superpowers/specs/` and `docs/superpowers/plans/`. The plan-driven Plan 1 is shipped; the doc still calls out group-play, profile and bag as "Plan 2", but those are in fact implemented.

## Common commands

```bash
# Node is via nvm — these commands need `source ~/.nvm/nvm.sh` first in fresh shells.
npm run dev              # Vite dev server on :5173
npm run build            # tsc -b && vite build
npm run test             # vitest watch
npm run test:run         # vitest run (CI mode)
npm run test:run -- src/services/scoring.test.ts   # single file
npm run lint             # eslint .
npx tsc --noEmit         # type-check only (no emit, no build)
```

Firebase CLI is installed globally via nvm. From a fresh terminal:

```bash
source ~/.nvm/nvm.sh
firebase deploy --only firestore   # deploys firestore.rules + firestore.indexes.json
firebase deploy --only hosting     # builds-must-have-run; deploys dist/ to Firebase Hosting
firebase projects:list             # verify CLI is authenticated
```

Setup steps for `.env.local`, Auth provider, Firestore creation, and Places API are in `SETUP.md`. Note that `SETUP.md` predates the group-play changes — the `/join/:code` deep-link route and the `lobbyCode + status` composite index aren't documented there yet.

## Architecture

### Layers (one-way dependency arrows)

```
screens/ → hooks/ + store/ + services/ + components/
hooks/   → services/
services/ → firebase.ts (only)
types/   ← imported by everyone (no inbound deps)
```

- `services/` is the **only** layer that imports `firebase/*`. Tests mock that boundary.
- `hooks/` wraps services in React subscription patterns (`useAuth`, `useProfile`, `useGeolocation`).
- `screens/` are full-page components. They subscribe via hooks and call services directly for mutations.
- `components/ui/` are pure presentational primitives (`Button`, `Card`, `ScoreChip`, `ClubChip`, `ConfirmDialog`); `components/layout/` is `PageHeader` and `BottomNav`.

### Data model — central source of truth

`src/types/index.ts` is the **canonical schema** for everything stored in Firestore. Some fields carry legacy versions for backwards compatibility — always use the helpers, not the raw fields:

- `HoleShots.clubs: string[]` is canonical. `HoleShots.club?: string` is the legacy "last club" field. Use `getHoleClubs(shots)` to read.
- `AppUser.bag: BagClub[]` is canonical. `AppUser.clubs?: string[]` is the legacy enabled-club list. Use `getBagFromUser(user)` to read.
- `Round.playerIds: string[]` is the denormalized membership array (required for the Firestore `array-contains` query in `getUserRounds`). Always maintained alongside `Round.players: Record<uid, PlayerInfo>` map.
- `BagClub.category?: ClubCategory` is backfilled by `getClubCategory(club)` from id when missing.

`normalizeRound(id, data)` in `services/rounds.ts` converts Firestore `Timestamp` → JS `Date` at the boundary so screens can use `date-fns` directly. This means `getDoc`-derived Round objects must always go through `normalizeRound`.

### State management

- **Firestore is the source of truth** for rounds and profiles. Screens subscribe via `subscribeToRound` / `subscribeToProfile` and re-render on snapshots.
- **`useAppStore` (Zustand)** holds only `lastClubUsed` (which club to default to when entering a new hole). Other fields exist but are dead — see `docs/superpowers/...` audit notes.
- **Optimistic UI pattern** in `HoleTracker`: `localClubs` state masks server snapshot until `lastSyncedKeyRef.current === serverKey` (server has caught up to our write). Reset on hole change, player switch, or save error.

### Group play & concurrency

`recordShot` uses `runTransaction` because two players can write the same `holes[i].shots[uid]` slot concurrently. Currently the transaction rewrites the **entire** `holes` array — this is a known scaling concern flagged in the audit; dot-path updates are the fix.

Round lifecycle is encoded in `RoundStatus`: `'lobby' | 'active' | 'finished'`. Solo rounds skip lobby (start at `'active'`). Group rounds start in `'lobby'` until the host calls `startRound`. `GroupLobby` and `HoleTracker` both subscribe to status changes and auto-navigate when it flips.

`joinRoundByCode(code)` queries `rounds where lobbyCode == code AND status == 'lobby'`. The matching Firestore composite index lives in `firestore.indexes.json`.

### Firestore security

`firestore.rules` is field-permissive right now (`status == 'lobby'` allows any auth user to update **any field** of the round, not just join-related fields). The security audit (see message history) flagged this as a **critical** issue to address before public users. When tightening, split `allow update` into per-action rules using `request.resource.data.diff(resource.data).affectedKeys()`.

### Routing

`src/App.tsx` has all routes. Every non-`/auth` route is wrapped in `<ProtectedRoute>` which checks `useAuth()` and redirects to `/auth` if no user. Catch-all `*` redirects to `/home`. Deep-link `/join/:code` auto-attempts to join once auth resolves.

### Testing

Vitest + jsdom + @testing-library/react. Test files live alongside their source (`Foo.test.ts(x)` next to `Foo.ts(x)`). When importing a module that transitively pulls in `firebase/*`, **mock Firebase before the import** — see `src/services/rounds.test.ts` for the standard `vi.mock('../firebase', ...)` + `vi.mock('firebase/firestore', ...)` pattern. Strict TypeScript means test fixtures must include `playerIds` and every required field of the `Round` type.

## Conventions

- **Russian copy** in all user-facing strings. The proper-plural helper `pluralRu(n, one, few, many)` exists inline in `CourseSearch.tsx` and should be the form used everywhere (other screens currently hard-code two-form fallbacks — known cleanup).
- **Touch targets ≥ 48 px** via Tailwind tokens `min-h-touch` / `min-w-touch`. Do not hard-code `min-h-[48px]`.
- **Numeric inputs in My Bag** use `defaultValue` + `onBlur` to commit; do not switch to controlled inputs without handling the auto-save UX.
- **Firestore writes always merge** for user profile (`setDoc(..., { merge: true })`) so partial updates from MyBag don't blow away other fields.
- After each shot write, `recordShot` also writes the legacy `club: lastUsedClub` field for backwards compatibility with old readers. Keep this in sync if you change the shape.

## Things to be aware of

- The CourseSearch screen calls the Google Places API **directly from the browser** with `VITE_GOOGLE_PLACES_API_KEY` in the bundle. This is acknowledged in `services/courses.ts` and protected via HTTP-referrer + API restriction. A Cloud Function proxy is on the roadmap.
- The bundle is ~609 kB (gzip ~185 kB) as one chunk. `React.lazy()` on the heavier screens (`HoleTracker`, `RoundResults`, `MyBag`, `GroupLobby`) would halve initial JS but isn't done yet.
- There is no `ErrorBoundary` and no Sentry. A render error in production produces a blank screen.
- No service worker. The app is "installable" via the manifest, but `vite-plugin-pwa` isn't wired up — there's no real offline support.
- README.md is the stock Vite template; SETUP.md is the real onboarding doc.
