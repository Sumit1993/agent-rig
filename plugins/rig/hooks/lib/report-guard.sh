#!/bin/bash
# report_guard <guard_id> <tool> [detail]
# Fire-and-forget. Never blocks, never fails the caller, never prints on stdout.
report_guard() {
  command -v mage >/dev/null 2>&1 || return 0

  local guard_id="${1:-}"
  local tool="${2:-}"
  local detail="${3:-}"

  [ -n "$guard_id" ] && [ -n "$tool" ] || return 0

  # jq first, python3 second: this machine carried no jq at all after the
  # 2026-09-16 rebuild, and bailing here meant a guard blocked without ever
  # reporting that it had.
  local payload
  if command -v jq >/dev/null 2>&1; then
    payload=$(jq -n \
      --arg guard_id "$guard_id" \
      --arg tool "$tool" \
      --arg detail "$detail" \
      '{"guard_id": $guard_id, "tool": $tool, "detail": $detail}' 2>/dev/null) || return 0
  elif command -v python3 >/dev/null 2>&1; then
    payload=$(RIG_GUARD_ID="$guard_id" RIG_TOOL="$tool" RIG_DETAIL="$detail" python3 -c '
import json, os
print(json.dumps({
    "guard_id": os.environ["RIG_GUARD_ID"],
    "tool": os.environ["RIG_TOOL"],
    "detail": os.environ["RIG_DETAIL"],
}))' 2>/dev/null) || return 0
  else
    return 0
  fi

  if command -v timeout >/dev/null 2>&1; then
    printf '%s\n' "$payload" | timeout 5 mage observe >/dev/null 2>&1 || true
  else
    printf '%s\n' "$payload" | mage observe >/dev/null 2>&1 || true
  fi

  return 0
} >/dev/null
