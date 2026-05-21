# Lessons — patterns to not repeat

> Per CLAUDE.md workflow #3: after **any** user correction, append a rule here
> phrased so the next session doesn't repeat the mistake.
> Re-read this file at the start of each session in this project.

## Active rules

- **Execute plan tasks one subagent at a time.** During plan execution
  (subagent-driven-development), dispatch a single plan task per implementer
  subagent and run both reviews (spec + quality) before the next task.
  Do not bundle plan tasks even if they look related.
  See `~/.claude/projects/.../memory/feedback_one_task_at_a_time.md`.
  _Source: user feedback during Plan 1 execution._

- **Security hardening that removes a capability must update the UI that
  relied on it.** Sprint 7 made `recordShot` self-only (anti-griefing) but
  left HoleTracker's player-switcher + `save(activeUserId)` path intact, so
  the host scoring for another player silently wrote to their own slot →
  the other player's counter "rolled back to 0". Rule: when locking down a
  callable/rules path, grep every client call site that passed the
  now-ignored argument and either restore the capability with proper
  authorization (host-or-self) or disable the orphaned UI.
  _Source: group-play bug report — host couldn't score the 2nd player._

- **`onSnapshot` without an error callback = silent infinite spinner.**
  `subscribeToRound`/`subscribeToProfile` omitted the error handler, so a
  permission/network failure never surfaced and screens spun on "Загрузка…"
  forever. Always pass the 3rd `onError` arg to `onSnapshot` and render a
  visible error + escape hatch.
  _Source: same report — 2nd player "couldn't connect, kept loading"._

- **Firestore dot-path updates do NOT support array indices.** Before
  recommending a path like `arr.0.field` for `tx.update`, verify the
  target field is a map, not an array. If it's an array, the choices are:
  (a) keep the full-array rewrite (acceptable for small arrays), or
  (b) refactor the field to `Record<string, T>` keyed by a stable id.
  _Source: Sprint 1 audit follow-up — the audit recommended dot-path for
  `recordShot`, but `holes` is an array, so the optimization was deferred
  in favor of in-transaction safety checks._
