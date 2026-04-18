---
name: Opus 4.7 era defaults
description: Preferred defaults on Opus 4.7 — xhigh effort, adaptive thinking (no fixed budgets), opusplan for large tasks, Haiku for subagents. Breaking API changes documented.
type: feedback
---

## Rule

On Opus 4.7 (GA 2026-04-16):

**Defaults to assume:**
- Model: `opus` alias (resolves to Opus 4.7 on Anthropic API)
- Effort: `xhigh` (new default; sits between `high` and `max`)
- Thinking: adaptive only — no fixed `budget_tokens`, no `MAX_THINKING_TOKENS`
- Context: 1M automatically on Max/Team/Enterprise; Pro needs extra-usage billing

**Cost-aware routing (applies on ALL plans):**
- `opusplan` alias for large agentic tasks → Opus reasons in plan mode, Sonnet executes
- `CLAUDE_CODE_SUBAGENT_MODEL=haiku` env var → worker agents route to Haiku
- `ANTHROPIC_DEFAULT_OPUS_MODEL=claude-opus-4-7` → pin version explicitly

**Breaking API changes to watch for in user's code:**
- `thinking: {type: "enabled", budget_tokens: N}` → returns 400 (use `{type: "adaptive"}`)
- `temperature`, `top_p`, `top_k` non-default → returns 400
- Thinking content omitted by default (use `display: "summarized"` to restore)
- Tokenizer uses ~1-1.35x more tokens; bump `max_tokens` and compaction triggers

## Why

Opus 4.7 replaces fixed thinking budgets with adaptive thinking and removes sampling params. Any inherited guidance written pre-2026-04-16 that references `MAX_THINKING_TOKENS`, `budget_tokens`, or fixed thinking modes is stale and may actively break API code.

## How to apply

1. When user asks about thinking/effort config on Opus 4.7 → recommend `effortLevel` in settings.json, not `MAX_THINKING_TOKENS`
2. When user writes API code for Opus 4.7 → flag any `budget_tokens`, `temperature`, `top_p`, `top_k` as breaking
3. When user has a multi-agent task → suggest `CLAUDE_CODE_SUBAGENT_MODEL=haiku` to halve cost
4. When user has a large planning+execution task → suggest `opusplan` alias
