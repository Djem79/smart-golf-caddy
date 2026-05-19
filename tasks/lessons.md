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

- **Firestore dot-path updates do NOT support array indices.** Before
  recommending a path like `arr.0.field` for `tx.update`, verify the
  target field is a map, not an array. If it's an array, the choices are:
  (a) keep the full-array rewrite (acceptable for small arrays), or
  (b) refactor the field to `Record<string, T>` keyed by a stable id.
  _Source: Sprint 1 audit follow-up — the audit recommended dot-path for
  `recordShot`, but `holes` is an array, so the optimization was deferred
  in favor of in-transaction safety checks._
