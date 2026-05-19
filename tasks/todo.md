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
