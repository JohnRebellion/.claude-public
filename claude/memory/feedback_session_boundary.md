---
name: Session boundary decision
description: After completing a multi-step task, evaluate stay vs. start-new and generate a handoff prompt if needed
type: feedback
---

## When to evaluate

Trigger this after: all todos completed, tests pass, build green, PR created, or user says "done" / "what's next" / "next task".

## Stay signals

Continue in the same session when:
- Next task shares >50% context with what's loaded (same files, same architectural understanding)
- No context compression has happened yet
- It's a direct continuation of the same feature (e.g., adding tests after implementing)
- Context is under ~60% capacity with high signal-to-noise (no bloat from debugging rabbit holes)

## Start-new signals

Recommend a new session when:
- Next task is in a different area (e.g., switching from backend Go to frontend Svelte, or from billing to deployment)
- Context has been compressed at least once
- Heavy exploration/debugging noise accumulated (failed approaches, large file reads that aren't needed anymore)
- User is switching from planning to implementation (clean context improves execution)
- Context is past ~60% capacity

## How to present

One short paragraph. Lead with the recommendation, then one sentence of reasoning. Don't pad it.

Example stay: "Context is still clean and the next task directly continues this work — stay in this session."

Example start-new: "The next task (Coturn integration) touches different infrastructure and the session has accumulated debugging context from the Wolf work — start fresh. Here's the handoff prompt:"

## Handoff prompt format

Generate a self-contained block the user can paste into a new session. Include:

1. **Completed work** — what was built/changed, file paths, key decisions made
2. **Architecture context** — only what the next task needs (not everything)
3. **What to avoid** — failed approaches, gotchas discovered, out-of-scope items
4. **Remaining tasks** — bulleted list
5. **Next best step** — the specific first action for the new session

Omit: debugging history, tool outputs, exploration tangents, anything the new session can read from code.

**Why:** Per research, "what didn't work and why" is the most valuable part of a handoff — prevents repeating failed approaches. Everything else should be derivable from reading the current code state.

## Follow-through — the harder half

Writing the handoff is step one. The failure mode: recommend "start fresh" → user asks a follow-up question in the same session → treat the question as authorization to keep going. **It isn't.** The recommendation stands until the user explicitly overrides it.

**How to apply:**
- After issuing a "start-new" recommendation with a handoff prompt, if the user's next message contains a new task (not "actually, stay"), re-raise the boundary in one line before executing: "Quick note — we said we'd start fresh here. Want me to continue in this session anyway, or hold for a new one?"
- Don't re-ask the full evaluation — one sentence, then either proceed or wait.
- Exception: if the user explicitly said "stay" / "keep going in this session" / equivalent, treat it as override and don't re-raise.

**Why:** Context bloat is the actual cost of ignoring a boundary. The handoff prompt only pays for itself if you actually use it. Shipping a recommendation and immediately ignoring it teaches the user the recommendation was noise — observed failure 2026-04-16: recommended new session, user asked "what's next" → I kept coding instead of re-raising.
