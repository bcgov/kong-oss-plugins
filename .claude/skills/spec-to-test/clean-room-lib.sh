#!/usr/bin/env bash
# Shared helpers for clean-room-on/off (sourced, not executed).
# shellcheck disable=SC2034

CLEAN_ROOM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEAN_ROOM_ROOT="$(cd "$CLEAN_ROOM_DIR/../../.." && pwd)"
CLEAN_ROOM_FLAG="$CLEAN_ROOM_ROOT/.claude/clean-room.active"
CLEAN_ROOM_PATTERNS="$CLEAN_ROOM_DIR/clean-room-patterns.txt"
CLEAN_ROOM_CURSORIGNORE="$CLEAN_ROOM_ROOT/.cursorignore"
CLEAN_ROOM_BEGIN="# BEGIN spec-to-test clean-room"
CLEAN_ROOM_END="# END spec-to-test clean-room"

clean_room_load_patterns() {
  grep -vE '^\s*(#|$)' "$CLEAN_ROOM_PATTERNS"
}

clean_room_cursorignore_block() {
  cat <<EOF
$CLEAN_ROOM_BEGIN
# Managed by .claude/skills/spec-to-test/clean-room-{on,off}.sh — do not edit by hand.
# Synced from clean-room-patterns.txt. Test output paths stay visible for generation.
$(clean_room_load_patterns)
$CLEAN_ROOM_END
EOF
}

clean_room_strip_cursorignore_block() {
  local ignore="$CLEAN_ROOM_CURSORIGNORE"
  [[ -f "$ignore" ]] || return 0
  grep -qF "$CLEAN_ROOM_BEGIN" "$ignore" || return 0

  local tmp
  tmp="$(mktemp)"
  awk -v begin="$CLEAN_ROOM_BEGIN" -v end="$CLEAN_ROOM_END" '
    $0 == begin { in_block = 1; next }
    in_block && $0 == end { in_block = 0; next }
    in_block { next }
    { lines[++n] = $0 }
    END {
      while (n > 0 && lines[n] == "") n--
      for (i = 1; i <= n; i++) print lines[i]
    }
  ' "$ignore" > "$tmp"

  if [[ ! -s "$tmp" ]]; then
    rm -f "$ignore" "$tmp"
  else
    mv "$tmp" "$ignore"
  fi
}
