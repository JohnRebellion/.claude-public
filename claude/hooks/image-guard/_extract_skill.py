#!/usr/bin/env python3
"""Read a PostToolUse JSON payload on stdin, print the skill/subagent name.

Prints the value of tool_input.skill (Skill tool) or tool_input.subagent_type
(Task/Agent tool), or nothing if neither is present or the payload is invalid.
Kept as a separate file so the shell hook needs no inline-python quoting.
"""
import json
import sys


def main() -> int:
    try:
        d = json.load(sys.stdin)
    except Exception:
        return 0
    ti = d.get("tool_input") or {}
    name = ti.get("skill") or ti.get("subagent_type") or ""
    if name:
        print(name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
