# Global Instructions

## Intent Clarification (CRITICAL — applies to every session)

Before starting any non-trivial work, ALWAYS clarify intent first:

1. **Ask before planning** — When a task involves implementation, architecture, or multi-step work: ask 1-3 targeted clarifying questions to confirm scope, constraints, and expected outcome before producing a plan or writing code.
2. **Ask before researching** — When a request is ambiguous or could go multiple directions: confirm what the user specifically wants before spending tokens.
3. **Skip clarification for obvious tasks** — Single-file edits, direct questions, bug fixes with clear reproduction, or explicit step-by-step instructions. Just do them.
4. **Never assume scale** — "add auth" or "set up CI" could be 5 lines or 500. Ask which.

**The threshold**: if you're about to spawn an agent, enter plan mode, or touch 3+ files — clarify first.

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
