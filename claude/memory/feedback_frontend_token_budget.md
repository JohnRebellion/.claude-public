---
name: Frontend multi-file token budget strategy
description: How to structure frontend development sessions to stay within Pro plan token limits. Covers research, component creation, and session splitting.
type: feedback
---

## Rule

Frontend UI/design-system work creates many files and burns tokens fast. Budget accordingly:

### Research phase
- Use ONE explore agent for codebase analysis (not two)
- For web research: use WebSearch + WebFetch directly in main session, NOT a research agent. Agent overhead is 2-3x the cost of direct search.
- Cap research at ~20K tokens before moving to implementation

### Implementation phase
- **Session 1**: Design tokens + component library (foundation). Commit.
- **Session 2**: Landing page + dashboard revamp. Commit.
- **Session 3**: Navigation overhaul + settings/feature pages. Commit.
- Never try to do all three in one session on Pro plan.

### File creation strategy
- Create file stubs via Bash (`touch`), then populate with Edit (lower gate friction)
- Write components in dependency order to catch type errors early
- Run `svelte-check` after every 5 files, not after every file
- Run build only at phase boundaries

## Why

**2026-04-16 incident:** Attempted full design system + landing page + dashboard + navigation in one Opus session. Two research agents (~120K tokens), 20 file creates with gateguard overhead (~150K tokens), type checking loops (~30K tokens). Session consumed majority of weekly budget.

## How to apply

1. At session start, estimate file count. If >8 new files, split across sessions.
2. Use Haiku/Sonnet for mechanical component creation; reserve Opus for architecture + complex pages. As of Opus 4.7, set `CLAUDE_CODE_SUBAGENT_MODEL=haiku` globally — worker agents (code-reviewer, build-resolver) auto-route to Haiku while main session stays on Opus/Sonnet.
3. Commit at each phase boundary so next session starts clean.
