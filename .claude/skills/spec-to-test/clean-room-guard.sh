#!/usr/bin/env bash
# Claude Code PreToolUse guard for spec-to-test clean-room.
# No-ops unless .claude/clean-room.active exists (set by clean-room-on.sh).
# Always registered in .claude/settings.json — safe for non-clean-room sessions.
# Preserves stdin (tool-call JSON) for the Python checker.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FLAG="$ROOT/.claude/clean-room.active"
PATTERNS="$SCRIPT_DIR/clean-room-patterns.txt"

if [[ ! -f "$FLAG" ]]; then
  exit 0
fi

exec python3 "$SCRIPT_DIR/clean-room-guard.py" "$ROOT" "$PATTERNS"
