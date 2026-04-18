---
name: Agent and research cost limits
description: Pro plan (200k tokens) cannot afford research agents. Use WebSearch+WebFetch direct. Never spawn parallel research agents on Pro.
type: feedback
---

## Rule

**Pro plan (200k tokens):**
- Never spawn research agents — use WebSearch + WebFetch directly in main session
- Research ≤ 4 RQs → handle sequentially in main session (~20-25k tokens total)
- Research 5+ RQs → split into multiple stubs (max 4 RQs each), run across separate sessions
- Reserve agent quota for implementation work (code review, builds, tests)
- Use `effort: low` or `effort: medium` for research-heavy work (research is data gathering, not deep reasoning). On Opus 4.7, adaptive thinking replaces fixed thinking budgets — `MAX_THINKING_TOKENS` no longer applies.

**Enterprise/Unlimited users:** up to 2 parallel agents is acceptable for research.

## Why

**2026-04-02 incident:** `/workspace.research STUB-035` launched 4 parallel agents for 7 RQs. 3 of 4 hit rate limit within 7 minutes before returning results. Only 1 agent completed (58K tokens).

**Follow-up analysis:** Even 2 agents at ~25k tokens each = 50k tokens per research session. With orchestration overhead (~10k), a single research session consumes ~30% of the Pro plan budget. Direct WebSearch + WebFetch costs 1/2 to 1/3 of agent-based research (~20-25k tokens for 7 RQs).

## How to apply

1. Default to WebSearch + WebFetch in main session for all research (no sub-agents)
2. For `/workspace.research`: check stub RQ count first. Pro users should not use agent-based parallelism at all
3. Agent quota is precious on Pro — spend it on implementation agents (code-reviewer, build-error-resolver, tdd-guide), not research
4. If a research task truly needs agents (rare): max 2, disable extended thinking, run sequentially not in parallel
5. For 5+ RQs: split into multiple stubs and research across separate sessions
