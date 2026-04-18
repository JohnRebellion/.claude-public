# Performance Optimization

## Model Selection Strategy

Model routing depends on the user's active plan (Pro vs Team/Enterprise). Defaults are stored in `~/.claude/memory/feedback_model_routing.md` — do not override them here.

**Model capabilities** (for reference, not defaults):
- **Haiku 4.5**: 90% of Sonnet capability, 3x cost savings — best for lightweight agents, worker agents
- **Sonnet 4.6**: Best coding model — complex coding, orchestration, multi-agent workflows
- **Opus 4.6**: Deep reasoning with fixed thinking budgets — legacy for accounts pinned to 4.6
- **Opus 4.7** (GA 2026-04-16): Most capable — adaptive thinking only, 1M context, default effort `xhigh`, high-res vision (3.75MP)

## Context Window Management

Avoid last 20% of context window for:
- Large-scale refactoring
- Feature implementation spanning multiple files
- Debugging complex interactions

Lower context sensitivity tasks:
- Single-file edits
- Independent utility creation
- Documentation updates
- Simple bug fixes

## Effort Levels + Plan Mode

Opus 4.7 uses **adaptive thinking** — the model decides when to think deeper based on task complexity. Fixed thinking budgets (`budget_tokens`, `MAX_THINKING_TOKENS`) return 400 errors on Opus 4.7.

Control reasoning depth via **effort levels** instead:

| Level    | Use case                                                                            |
| :------- | :---------------------------------------------------------------------------------- |
| `low`    | Short, latency-sensitive tasks — not intelligence-sensitive                         |
| `medium` | Cost-sensitive work where some intelligence tradeoff is acceptable                  |
| `high`   | Balanced — minimum for intelligence-sensitive work                                  |
| `xhigh`  | **Default on Opus 4.7** — best for most coding and agentic tasks                    |
| `max`    | Session-only; reserve for genuinely hard problems; prone to overthinking            |

Set the level via:
- **`/effort`** command in-session (interactive picker or `/effort xhigh`)
- **`effortLevel`** key in `~/.claude/settings.json` (persists across sessions)
- **`CLAUDE_CODE_EFFORT_LEVEL`** env var (overrides settings)
- **`--effort <level>`** CLI flag

For complex tasks requiring deep reasoning:
1. Bump effort to `xhigh` or `max` (session-scoped)
2. Enable **Plan Mode** for structured approach
3. Use multiple critique rounds for thorough analysis
4. Use split role sub-agents for diverse perspectives

**Legacy note (Opus 4.6 / Sonnet 4.6 only):** `MAX_THINKING_TOKENS` and `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1` still work on 4.6 models. Do not use these on Opus 4.7 — they are removed.

## Build Troubleshooting

If build fails:
1. Use **build-error-resolver** agent
2. Analyze error messages
3. Fix incrementally
4. Verify after each fix
