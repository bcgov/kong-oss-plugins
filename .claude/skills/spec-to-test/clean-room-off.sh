#!/usr/bin/env bash
# Disable clean-room after a spec-to-test run (Cursor + Claude Code).
#
# - Removes .claude/clean-room.active (Claude guard no-ops)
# - Removes only the managed block from repo-root .cursorignore
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=clean-room-lib.sh
source "$SCRIPT_DIR/clean-room-lib.sh"

cd "$CLEAN_ROOM_ROOT"

if [[ -f "$CLEAN_ROOM_FLAG" ]]; then
  rm -f "$CLEAN_ROOM_FLAG"
  echo "clean-room flag off: removed $CLEAN_ROOM_FLAG"
else
  echo "clean-room flag already off"
fi

if [[ -f "$CLEAN_ROOM_CURSORIGNORE" ]] && grep -qF "$CLEAN_ROOM_BEGIN" "$CLEAN_ROOM_CURSORIGNORE"; then
  clean_room_strip_cursorignore_block
  if [[ -f "$CLEAN_ROOM_CURSORIGNORE" ]]; then
    echo "clean-room Cursor: removed managed block from $CLEAN_ROOM_CURSORIGNORE"
  else
    echo "clean-room Cursor: removed empty $CLEAN_ROOM_CURSORIGNORE"
  fi
else
  echo "clean-room Cursor: no managed block"
fi
