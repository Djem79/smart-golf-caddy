# Tasks — Sprint 7 (P0 Hotfix from audit)

Source: 2026-05-19 multi-agent audit (security + architecture + UX + prod
readiness). 4 critical findings; this sprint addresses all four.

## Active

- [ ] **1. `shareRoundByEmail` lockdown — close open-relay**
  - Restrict `toEmail` to one of:
    - caller's own auth email (request.auth.token.email)
    - any participant's `players[*].email` in the round
  - Reject arbitrary external recipients with `invalid-argument`.
  - Add per-user daily counter at `userQuota/{uid}` collection:
    ```ts
    { day: 'YYYY-MM-DD', count: number }
    ```
    Limit: 10 shares/day. Atomic increment via Firestore transaction.
  - Tighten email regex to reject control chars (header-injection defence).
  - **No App Check yet** — defer to P1 (client-side integration cost).

- [ ] **2. `recordShot` → callable — close cross-player griefing**
  - New callable `recordShotV2(roundId, holeIndex, clubs)`:
    - Verifies `request.auth.uid` is in `round.playerIds`.
    - Writes to `holes[holeIndex].shots[request.auth.uid]` only.
    - Server-side dot-path update (so no full-array rewrite — pre-fix
      for scaling).
  - Migrate `services/rounds.ts → recordShot` to call the callable.
  - Tighten `firestore.rules` RECORD SHOT branch: forbid all client
    `holes` writes. Only Admin SDK (via the callable) may write.
  - Backwards compat: legacy in-progress rounds still work because
    rules apply to writes, not reads.

- [ ] **3. Tighten `allow get` on rounds — close lobby PII leak**
  - Remove `resource.data.status == 'lobby'` from public-read exception.
  - Move lobby-by-code lookup to a callable `joinLobbyByCode(code)`:
    - Uses Admin SDK to find lobby, add user atomically.
    - Returns roundId on success, null on not-found.
  - Update `services/rounds.ts → joinRoundByCode` to call the callable.
  - Drop the now-unused `lobbyCode + status` Firestore composite index?
    Leave for now; no harm in keeping.

- [ ] **4. `onRoundFinished` atomic idempotency + per-uid tracking**
  - At handler entry: Firestore transaction that:
    - Reads current round
    - If `emailedAt` exists OR `emailingStartedAt` is recent (<5 min):
      exit
    - Otherwise sets `emailingStartedAt: serverTimestamp()`
  - Track per-uid success in `emailedTo: { uid: true }` map.
  - At end: set `emailedAt: serverTimestamp()` only if ALL playerIds
    are present in `emailedTo` map.
  - Partial-failure recovery: a manual re-trigger can resume only the
    still-missing uids (see `emailedTo` check before send).
  - Move `emailResults[].email` PII into a redacted form (`u****@gmail`)
    to comply with #12 from prod audit.

## Verification gate

- `npx tsc --noEmit` (root + functions/) clean
- `npm run lint` clean
- `npm run test:run` — 113/113 minimum
- `npm run build` succeeds
- Manual:
  - Finish a solo round → email arrives → re-finish (revert status →
    set finished) → no duplicate email
  - Share dialog → arbitrary email like `attacker@example.com` →
    rejected with clear error
  - Share dialog → your own email → succeeds
  - Try to write to `rounds/{otherId}` while not a participant → denied
- Deploy: `firebase deploy --only functions,firestore,hosting`

## Review

_(filled after sprint)_
