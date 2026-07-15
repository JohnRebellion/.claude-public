# Performance Optimization

## Model Selection Strategy

Model routing depends on the user's active plan and session model. Defaults are stored in `~/.claude/memory/feedback_model_routing.md` — do not override them here.

**Current family** (Claude 5 era, as of 2026-07):
- **Haiku 4.5**: cheapest — worker/exploration subagents (`CLAUDE_CODE_SUBAGENT_MODEL=haiku`)
- **Sonnet 5**: best cost/capability for routine coding
- **Opus 4.8** ($5/$25 per Mtok): default for hard coding; supports fast mode (/fast)
- **Fable 5** ($10/$50 per Mtok, 2x Opus): frontier tier — long-horizon, multi-stage, hard-reasoning tasks. Often finishes in fewer turns/tokens, so cost-per-task can beat Opus on hard work; on short well-scoped tasks Opus is cheaper. Route hard jobs to Fable, default the rest to Opus/Sonnet.

## Context Window Management

Avoid last 20% of context window for large refactoring, multi-file features, complex debugging. Single-file edits, docs, and simple fixes are context-insensitive.

## Effort Levels

Adaptive thinking only — no fixed thinking budgets (`budget_tokens` / `MAX_THINKING_TOKENS` are removed on 4.7+ models and return 400s).

| Level    | Use case                                                    |
| :------- | :---------------------------------------------------------- |
| `low`    | Latency-sensitive, mechanical tasks                          |
| `medium` | Cost-sensitive work, mild intelligence tradeoff acceptable   |
| `high`   | Minimum for intelligence-sensitive work                      |
| `xhigh`  | Default for most coding/agentic tasks                        |
| `max`    | Session-only; genuinely hard problems; prone to overthinking |

Set via `/effort` in-session, `effortLevel` in settings.json, `CLAUDE_CODE_EFFORT_LEVEL`, or `--effort`.

## Build Troubleshooting

If build fails: use **build-error-resolver** (or language-specific resolver), fix incrementally, verify after each fix.
