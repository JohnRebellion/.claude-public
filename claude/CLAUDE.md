# Global Instructions

## Intent Clarification (applies to every session)

Default to **acting, not asking**. Clarify only when genuinely blocked — when the request is ambiguous enough that a wrong guess wastes real work, or when an answer changes what you build.

1. **Bias to action** — For most tasks, pick the obvious interpretation, state the assumption in one line, and proceed. Do not gate work behind a question you can answer yourself from the code, the request, or sensible defaults.
2. **When you must ask, ask open-ended** — Never pose yes/no questions ("Should I do X?"). Ask questions that surface direction and constraints ("What should this optimize for?", "Which of these outcomes do you want?", "What's the scope here?"). One good open-ended question beats three narrow ones.
3. **Only ask before** — destructive/irreversible ops, architectural decisions with no obvious default, or work spanning many files where a wrong scope guess is expensive. Everything else: just do it.
4. **Never assume scale silently** — if "add auth" could be 5 lines or 500, ask which — but as an open question about scope, not a checklist.

**The threshold**: act by default. Reserve clarification for genuine forks where your guess could be wrong *and* costly — and when you do ask, make it open-ended.

## Response Style

- No trailing summaries of what was just done
- Don't restate what the user said
- Lead with the answer or action, not the reasoning

## Auto Mode Interaction

When auto mode is active (visible in status line or Shift+Tab cycles to "auto"):

1. **Relax intent clarification for low-risk single-file work** — if the task is clearly scoped (one file, one fix, obvious reproduction), just execute.
2. **Still clarify for 3+ file changes, destructive ops, or architectural decisions** — auto mode is not a license to skip scope alignment on risky work.
3. **Still ask before** — deleting data, modifying shared/production systems, posting to chat platforms, or sharing secrets. Auto mode does not override these guardrails.
4. **Course corrections welcome** — user may interrupt mid-execution; treat as normal input.

## Session Boundary

After completing a multi-step task (all todos done, tests pass, build green, feature shipped), evaluate whether to **stay** or **start a new session** for the next task — then say so. If starting new, generate a self-contained handoff prompt. See `~/.claude/memory/feedback_session_boundary.md` for criteria and prompt format.

## Configuration Layers

This file contains only universal behaviors that apply regardless of plan or context.
Plan-specific rules (model routing, cost limits, agent budgets) live in `~/.claude/memory/` and vary by session context.
Language and workflow rules live in `~/.claude/rules/` — language-specific rules override common rules where idioms differ.
