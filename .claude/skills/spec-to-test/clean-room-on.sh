#!/usr/bin/env bash
# Enable clean-room for a spec-to-test run (Cursor + Claude Code).
#
# - Creates .claude/clean-room.active (Claude PreToolUse guard becomes active)
# - Syncs a managed block into repo-root .cursorignore from clean-room-patterns.txt
#
# Does NOT ignore test output paths so generation can write/delete there.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=clean-room-lib.sh
source "$SCRIPT_DIR/clean-room-lib.sh"

cd "$CLEAN_ROOM_ROOT"

mkdir -p "$(dirname "$CLEAN_ROOM_FLAG")"
if [[ -f "$CLEAN_ROOM_FLAG" ]]; then
  echo "clean-room flag already present: $CLEAN_ROOM_FLAG"
else
  printf 'spec-to-test clean-room active\n' > "$CLEAN_ROOM_FLAG"
  echo "clean-room flag on: $CLEAN_ROOM_FLAG"
fi

# Refresh Cursor block from patterns (idempotent replace).
clean_room_strip_cursorignore_block
BLOCK="$(clean_room_cursorignore_block)"
if [[ -f "$CLEAN_ROOM_CURSORIGNORE" ]] && [[ -s "$CLEAN_ROOM_CURSORIGNORE" ]]; then
  printf '\n%s\n' "$BLOCK" >> "$CLEAN_ROOM_CURSORIGNORE"
else
  printf '%s\n' "$BLOCK" > "$CLEAN_ROOM_CURSORIGNORE"
fi
echo "clean-room Cursor: synced managed block to $CLEAN_ROOM_CURSORIGNORE"
echo "Tip: start a fresh agent chat after enabling for strongest isolation."
