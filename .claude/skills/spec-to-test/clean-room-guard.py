#!/usr/bin/env python3
"""Claude Code PreToolUse clean-room checker. Reads tool-call JSON on stdin."""
from __future__ import annotations

import fnmatch
import json
import os
import re
import sys


def load_patterns(path: str) -> list[str]:
    out: list[str] = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            out.append(line)
    return out


def to_rel(path: str, root: str) -> str:
    path = path.strip().strip("'\"")
    if not path:
        return ""
    path = os.path.expanduser(path)
    if os.path.isabs(path):
        try:
            path = os.path.relpath(path, root)
        except ValueError:
            return path
    return path.replace("\\", "/").lstrip("./")


def path_forbidden(path: str, root: str, patterns: list[str]) -> bool:
    rel = to_rel(path, root)
    if not rel or rel.startswith(".."):
        return False
    for pat in patterns:
        if pat.endswith("/"):
            base = pat.rstrip("/")
            parts = rel.split("/")
            for i in range(len(parts)):
                prefix = "/".join(parts[: i + 1])
                if fnmatch.fnmatch(prefix, base):
                    return True
        else:
            if fnmatch.fnmatch(rel, pat) or fnmatch.fnmatch(os.path.basename(rel), pat):
                return True
            if fnmatch.fnmatch(rel, "*/" + pat):
                return True
    return False


def command_forbidden(cmd: str, root: str, patterns: list[str]) -> bool:
    if not cmd:
        return False
    for token in re.findall(r"[^\s;|&]+", cmd):
        token = token.strip("'\"")
        if token.startswith("-"):
            continue
        if path_forbidden(token, root, patterns):
            return True
    for pat in patterns:
        needle = pat.rstrip("/")
        if "*" not in needle and needle in cmd:
            return True
        if needle.endswith("src") and re.search(r"plugins/.+/src(/|\b)", cmd):
            return True
    return False


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: clean-room-guard.py <repo-root> <patterns-file>", file=sys.stderr)
        return 0

    root = os.path.abspath(sys.argv[1])
    patterns = load_patterns(sys.argv[2])

    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0

    tool = data.get("tool_name") or ""
    inp = data.get("tool_input") or {}

    deny_reason = None
    for key in ("file_path", "path", "target_directory"):
        val = inp.get(key)
        if isinstance(val, str) and val and path_forbidden(val, root, patterns):
            deny_reason = f"clean-room: forbidden path {val}"
            break

    if deny_reason is None and tool in ("Bash", "Shell"):
        cmd = inp.get("command") or ""
        if command_forbidden(cmd, root, patterns):
            deny_reason = "clean-room: forbidden path referenced in shell command"

    if deny_reason is None and tool == "Glob":
        gp = inp.get("glob_pattern") or ""
        norm = gp.replace("\\", "/")
        if path_forbidden(gp, root, patterns) or (
            "plugins/" in norm and "/src" in norm
        ):
            deny_reason = f"clean-room: forbidden glob {gp}"

    if deny_reason:
        print(
            json.dumps(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": deny_reason
                        + " (spec-to-test clean-room; run clean-room-off.sh when done)",
                    }
                }
            )
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
