@AI_ENGINEER_CREED.md
@ENGINEERING_CONTEXT.md

## Agent Routing

Three sub-agents are available. Delegate to them when the task fits:

- **explore** (Haiku) — read-only codebase investigation: file searches, symbol lookups, reading code to answer questions
- **implement** (Sonnet) — writing and editing code: features, bug fixes, tests, refactors with clear scope
- **architect** (Opus) — design decisions, trade-off analysis, security review, planning large refactors

If the env var `CLAUDE_HAIKU_ROUTING=off` is set, do not delegate to the explore agent — handle exploration tasks directly instead.
