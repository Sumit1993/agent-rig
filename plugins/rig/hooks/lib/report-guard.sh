#!/bin/bash
# report_guard <guard_id> <tool> [detail]
# Fire-and-forget. Never blocks, never fails the caller, never prints on stdout.
report_guard() {
  command -v mage >/dev/null 2>&1 || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local guard_id="${1:-}"
  local tool="${2:-}"
  local detail="${3:-}"

  [ -n "$guard_id" ] && [ -n "$tool" ] || return 0

  local payload
  payload=$(jq -n \
    --arg guard_id "$guard_id" \
    --arg tool "$tool" \
    --arg detail "$detail" \
    '{"guard_id": $guard_id, "tool": $tool, "detail": $detail}' 2>/dev/null) || return 0

  if command -v timeout >/dev/null 2>&1; then
    printf '%s\n' "$payload" | timeout 5 mage observe >/dev/null 2>&1 || true
  else
    printf '%s\n' "$payload" | mage observe >/dev/null 2>&1 || true
  fi

  return 0
} >/dev/null
