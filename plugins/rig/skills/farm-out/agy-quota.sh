#!/bin/bash
# Atomic quota state per agy quota group. agy meters two groups, not one lane per
# model: Gemini Flash and Gemini Pro share a pool, Claude Opus, Claude Sonnet and
# GPT-OSS share the other. Issues #47, #118.
set -u

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/agy"
STATE_FILE="$STATE_DIR/quota.json"

read_state() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "{}"
    return
  fi
  if [ -f "$STATE_FILE" ] && jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1; then
    cat "$STATE_FILE"
  else
    echo "{}"
  fi
}

write_state() {
  local content="$1"
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  local tmp_file="$STATE_DIR/quota.json.tmp.$$.$RANDOM"
  if printf '%s\n' "$content" > "$tmp_file" 2>/dev/null; then
    mv -f "$tmp_file" "$STATE_FILE" 2>/dev/null || rm -f "$tmp_file" 2>/dev/null
  fi
}

group_for() {
  case "$1" in
    gemini*) echo "gemini" ;;
    claude*|gpt*) echo "claude-gpt" ;;
    *) echo "$1" ;;
  esac
}

parse_iso_reset() {
  local raw="$1"
  if [ -z "$raw" ] || [ "$raw" = "null" ]; then
    return
  fi
  local str="$raw"
  local h=0 m=0 s=0 matched=0
  if [[ "$str" =~ ^([0-9]+)h ]]; then h="${BASH_REMATCH[1]}"; str="${str#*h}"; matched=1; fi
  if [[ "$str" =~ ^([0-9]+)m ]]; then m="${BASH_REMATCH[1]}"; str="${str#*m}"; matched=1; fi
  if [[ "$str" =~ ^([0-9]+)s ]]; then s="${BASH_REMATCH[1]}"; str="${str#*s}"; matched=1; fi
  if [ "$matched" -eq 1 ] && [ -z "$str" ]; then
    local total=$((h * 3600 + m * 60 + s))
    date -u -d "+$total seconds" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
    return
  fi
  date -u -d "$raw" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}

cmd_record() {
  local model
  model=$(group_for "$1")
  local raw_reset="${2:-}"
  if ! command -v jq >/dev/null 2>&1; then
    return 0
  fi
  local reset_iso=""
  if [ -n "$raw_reset" ] && [ "$raw_reset" != "null" ]; then
    reset_iso=$(parse_iso_reset "$raw_reset")
  fi
  local exhausted_at
  exhausted_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local current
  current=$(read_state)
  local updated
  updated=$(printf '%s' "$current" | jq --arg m "$model" --arg ex "$exhausted_at" --arg reset "$reset_iso" '
    . + {
      ($m): {
        exhausted_at: $ex,
        reset_at: (if $reset == "" or $reset == "null" then null else $reset end)
      }
    }
  ' 2>/dev/null)
  if [ -n "$updated" ]; then
    write_state "$updated"
  fi
}

cmd_check() {
  local model
  model=$(group_for "$1")
  if ! command -v jq >/dev/null 2>&1; then
    echo "usable: jq is not available, skipping quota check"
    return 0
  fi
  local current
  current=$(read_state)
  local entry
  entry=$(printf '%s' "$current" | jq -c --arg m "$model" '.[$m] // empty' 2>/dev/null)
  if [ -z "$entry" ] || [ "$entry" = "null" ]; then
    echo "usable: $model has no quota record"
    return 0
  fi
  local reset_at
  reset_at=$(printf '%s' "$entry" | jq -r '.reset_at // empty' 2>/dev/null)
  local exhausted_at
  exhausted_at=$(printf '%s' "$entry" | jq -r '.exhausted_at // empty' 2>/dev/null)
  local now_epoch
  now_epoch=$(date -u +%s)

  if [ -n "$reset_at" ] && [ "$reset_at" != "null" ]; then
    local reset_epoch
    reset_epoch=$(date -u -d "$reset_at" +%s 2>/dev/null || echo 0)
    if [ "$reset_epoch" -gt "$now_epoch" ]; then
      local rem=$((reset_epoch - now_epoch))
      echo "exhausted: $model quota reset at $reset_at (${rem}s remaining)"
      return 1
    else
      echo "usable: $model quota reset at $reset_at has passed"
      return 0
    fi
  else
    local window="${AGY_QUOTA_UNKNOWN_RESET_SECONDS:-3600}"
    case "$window" in
      ''|*[!0-9]*) window=3600 ;;
    esac
    local exhausted_epoch
    exhausted_epoch=$(date -u -d "$exhausted_at" +%s 2>/dev/null || echo 0)
    local expiry_epoch=$((exhausted_epoch + window))
    if [ "$now_epoch" -lt "$expiry_epoch" ]; then
      local rem=$((expiry_epoch - now_epoch))
      echo "exhausted: $model quota exhausted at $exhausted_at (fallback window ${window}s, ${rem}s remaining)"
      return 1
    else
      echo "usable: $model fallback window of ${window}s from $exhausted_at has passed"
      return 0
    fi
  fi
}

cmd_clear() {
  local model
  model=$(group_for "$1")
  if ! command -v jq >/dev/null 2>&1; then
    return 0
  fi
  local current
  current=$(read_state)
  local updated
  updated=$(printf '%s' "$current" | jq --arg m "$model" 'del(.[$m])' 2>/dev/null)
  if [ -n "$updated" ]; then
    write_state "$updated"
  fi
}

cmd_record_from_envelope() {
  local model="$1"
  local file="${2:-}"
  if ! command -v jq >/dev/null 2>&1; then
    return 0
  fi
  if [ -z "$file" ] || [ ! -r "$file" ]; then
    echo "record-from-envelope: no envelope at $file" >&2
    exit 3
  fi
  local err_msg
  err_msg=$(jq -r 'if .error | type == "string" then .error elif .error != null then (.error | tostring) else "" end' "$file" 2>/dev/null || true)
  local err_lower
  err_lower=$(printf '%s' "$err_msg" | tr '[:upper:]' '[:lower:]')
  if ! (printf '%s' "$err_lower" | grep -q 'quota' && printf '%s' "$err_lower" | grep -qE 'reached|resource[_ ]exhausted|429'); then
    return 0
  fi
  local reset_arg=""
  if [[ "$err_msg" =~ [Rr]esets?[[:space:]]+in[[:space:]]+([0-9]+[hms][0-9hms]*) ]]; then
    reset_arg="${BASH_REMATCH[1]}"
  elif [[ "$err_msg" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(Z|[+-][0-9]{2}:?[0-9]{2})?) ]]; then
    reset_arg="${BASH_REMATCH[1]}"
  fi
  if [ -n "$reset_arg" ]; then
    cmd_record "$model" "$reset_arg"
  else
    cmd_record "$model"
  fi
  echo "recorded: $(group_for "$model") group quota exhausted via $model (reset ${reset_arg:-unknown})"
  return 0
}

cmd_live() {
  if ! command -v agy >/dev/null 2>&1; then
    echo "live quota unavailable: agy command not found"
    exit 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "live quota unavailable: jq command not found"
    exit 0
  fi
  local timeout_sec="${AGY_QUOTA_TIMEOUT:-60}"
  local raw_out rc=0
  raw_out=$(timeout "$timeout_sec" agy -p "/quota" --output-format json 2>/dev/null) || rc=$?
  if [ "$rc" -eq 124 ]; then
    echo "live quota unavailable: agy timed out after ${timeout_sec}s"
    exit 0
  elif [ "$rc" -ne 0 ] || [ -z "$raw_out" ]; then
    echo "live quota unavailable: agy command failed (rc=$rc)"
    exit 0
  fi
  local parsed
  parsed=$(printf '%s' "$raw_out" | jq -r '
    .command.data.groups // empty |
    if type != "array" or length == 0 then empty else
      .[] |
      def b(w): (.buckets[]? | select(.window == w or (.id? and (.id | endswith(w)))));
      (b("5h") // null) as $b5 |
      (b("weekly") // null) as $bw |
      if $b5 == null or $bw == null then
        "\((.name // "Unknown group")): unavailable (bucket missing)"
      else
        "\((.name // "Unknown group")): 5h \((($b5.remaining_fraction // 0) * 100) | round)% (resets \($b5.reset_time // "none")), weekly \((($bw.remaining_fraction // 0) * 100) | round)% (resets \($bw.reset_time // "none"))"
      end
    end' 2>/dev/null)
  if [ -z "$parsed" ]; then
    echo "live quota unavailable: unparseable quota json"
    exit 0
  fi
  printf '%s\n' "$parsed"
  exit 0
}

action="${1:-}"

if [ "$action" = "live" ]; then
  cmd_live
fi

model="${2:-}"

if [ -z "$action" ] || [ -z "$model" ]; then
  echo "Usage: agy-quota.sh live | record <model> [reset_at] | record-from-envelope <model> <file> | check <model> | clear <model>" >&2
  echo "State is keyed by quota group: any gemini* slug is 'gemini', any claude*/gpt* slug is 'claude-gpt'." >&2
  exit 2
fi

case "$action" in
  live)
    cmd_live
    ;;
  record)
    cmd_record "$model" "${3:-}"
    ;;
  record-from-envelope)
    cmd_record_from_envelope "$model" "${3:-}"
    ;;
  check)
    cmd_check "$model"
    ;;
  clear)
    cmd_clear "$model"
    ;;
  *)
    echo "Usage: agy-quota.sh live | record <model> [reset_at] | record-from-envelope <model> <file> | check <model> | clear <model>" >&2
    echo "State is keyed by quota group: any gemini* slug is 'gemini', any claude*/gpt* slug is 'claude-gpt'." >&2
    exit 2
    ;;
esac
