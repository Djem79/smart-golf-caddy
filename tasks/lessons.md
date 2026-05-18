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
