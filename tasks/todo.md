# Tasks — Sprint 3 (production hardening, docs, CI)

Source: audit synthesis 2026-05-19 + Sprint 2 leftover items.

## Active

_(no active task — Sprint 3 done)_

## Verification gate

- ✅ `npx tsc --noEmit` clean
- ✅ `npm run test:run` — 96/96 passing
- ✅ `npm run lint` — 0 errors, 0 warnings
- ✅ `npm run build` succeeds; service worker generated
- ⏭️ CI workflow runs green on the next push (will verify in GitHub)

## Review

### What shipped

- [x] **1. README + SETUP.md rewritten**
  - README.md replaced the stock Vite template with a real project
    overview: features, stack, commands, structure, doc links.
  - SETUP.md updated for Places API (New), the "Browser key vs API
    key 2" distinction (Identity Toolkit must stay allowed), Firestore
    field-aware rules + 2 composite indexes, group-play deep-link
    `/join/:code`, Authorized domains note, expanded troubleshooting
    table including the `auth/requests-to-this-api-identitytoolkit-...`
    error users may hit.

- [x] **2. GitHub Actions CI workflow** (`.github/workflows/ci.yml`)
  - On push + PR to main: `npm ci → lint → tsc --noEmit → test:run →
    build`. Build runs with placeholder VITE_* env vars (real keys
    aren't needed for static replacement to succeed).
  - Concurrency cancel-in-progress keeps runs cheap.

- [x] **3. Lint cleanup — 8 `react-hooks/set-state-in-effect` errors → 0**
  - Most were legitimate subscribe/sync patterns the rule can't
    distinguish from cascading-render bugs. Added eslint-disable lines
    with per-case rationale explaining why each is safe (subscriber
    init, snapshot-driven sync, async-side-effect kick-off, etc).
  - Touched useGeolocation, useProfile, CourseSearch, HoleTracker,
    MyBag.

- [x] **4. vite-plugin-pwa for real offline support**
  - Installed `vite-plugin-pwa` + `workbox-window`.
  - Auto-update SW registration, no user prompt.
  - Precaches the app shell (JS/CSS/HTML/icons/fonts).
  - Runtime caching: Google Place Photos (CacheFirst, 7d, 100 entries)
    and Google Fonts (StaleWhileRevalidate, 30d).
  - Keeps our custom `public/manifest.json` (manifest: false).
  - Build output: precache 735 KiB across 20 entries, plus sw.js +
    workbox-*.js.

- [x] **5. Sentry error monitoring**
  - `@sentry/react` installed.
  - New `src/sentry.ts` exporting `initSentry()` + `captureError()`.
    Both are no-ops when `VITE_SENTRY_DSN` is unset (dev/CI).
  - `main.tsx` calls `initSentry()` before render.
  - `ErrorBoundary.componentDidCatch` now forwards to `captureError`
    with the component stack as extra context.
  - `.env.example` gained the optional `VITE_SENTRY_DSN` line.

### Lessons captured

(no new lessons — set-state-in-effect rationale is documented inline
in code comments rather than as a project-wide rule.)

### Not done (intentionally deferred)

- **Cloud Function proxy for Places API** — would remove the API key
  from the browser bundle, but requires moving the Firebase project
  to the Blaze (pay-as-you-go) plan. User chose to defer.
- **Custom course library** — let users save hole layouts (par,
  distances per tee) per place so the next round at the same course
  preloads. Idea raised when discussing absent Garmin / Golfbert
  coverage for Russian courses. New sprint candidate.
