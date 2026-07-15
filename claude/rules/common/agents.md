# Agent Orchestration

The harness lists available agents each session — don't duplicate that here.

## Immediate Agent Usage

No user prompt needed:
1. Complex feature request → **planner**
2. Code just written/modified → **code-reviewer** (language-specific variant if one exists)
3. Bug fix or new feature → **tdd-guide**
4. Architectural decision → **architect**

## Parallel Execution

Launch independent agents in a single message (parallel), never sequentially. For complex problems, use split-role sub-agents with distinct lenses (factual, senior engineer, security, consistency, redundancy).
