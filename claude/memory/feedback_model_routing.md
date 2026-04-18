---
name: Default model routing (plan-dependent)
description: Model routing defaults that vary by active plan — Haiku default on Pro, full model access on Team. Always clarify intent before planning regardless of plan.
type: feedback
---

## Pro Plan ($20/mo personal)

- **Default**: Haiku for all work (coding, research, conversation, execution)
- **Plan mode**: Sonnet while actively in plan mode
- **After plan mode**: revert to Haiku

## Team Plan (employer-provided)

- Use the model the session is running on — no artificial downgrading
- Opus and Sonnet are available; use them at full capability

## Universal (both plans)

- **Always clarify intent before planning** — this is enforced in `~/.claude/CLAUDE.md`
- Skills or commands that specify a model override these defaults
- User explicitly requesting a model overrides these defaults

## Opus 4.7 era defaults (both plans)

Cost-optimization patterns that work on Pro and Team:

- **`opusplan` alias** — use for large agentic tasks. Opus reasons in plan mode, Sonnet executes. Cheaper than Opus throughout, smarter than Sonnet throughout.
- **`CLAUDE_CODE_SUBAGENT_MODEL=haiku`** — worker agents (code-reviewer, build-resolver, tdd-guide) auto-route to Haiku while main session stays on Opus/Sonnet. Roughly halves agent cost.
- **`ANTHROPIC_DEFAULT_OPUS_MODEL=claude-opus-4-7`** — pin version explicitly. Aliases update over time; pinning controls when you migrate.
- **`effortLevel: "xhigh"`** in settings.json is the Opus 4.7 default; only bump to `max` for session-scoped hard problems.

**Why:** Pro plan has tight token/cost limits. Team plan does not. Hardcoding Haiku as global default would cripple Team plan sessions. The intent clarification rule applies everywhere because wasted planning effort is expensive on any plan. The Opus 4.7 cost-optimization patterns cut cost on BOTH plans without sacrificing quality.

**How to apply:**
1. Check which plan context you're in (Pro vs Team) — if unclear, ask
2. Apply the matching routing above
3. Apply Opus 4.7 era defaults regardless of plan
4. Always clarify before planning regardless of plan
