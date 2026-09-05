#!/bin/bash
# Append before render so a broken status line never drops the capture.
# Lines are built in memory so concurrent appends do not interleave. Refs #48.
if ! command -v jq >/dev/null 2>&1; then
  printf '%b' "agy"
  exit 0
fi

input=$(cat)

if [ -n "$input" ]; then
  now=$(date -u +'%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true)
  record=$(printf '%s' "$input" | jq -c --arg ts "$now" '
    if type == "object" then . + {captured_at: $ts} else empty end
  ' 2>/dev/null || true)

  if [ -n "$record" ]; then
    out_dir="${XDG_DATA_HOME:-$HOME/.local/share}/agy-runs"
    mkdir -p "$out_dir" 2>/dev/null || true
    printf '%s\n' "$record" >> "$out_dir/statusline.ndjson" 2>/dev/null || true
  fi
fi

model=$(printf '%s' "$input" | jq -r '.model.id // .model.display_name // empty' 2>/dev/null || true)
used=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null || true)

quota_info=$(printf '%s' "$input" | jq -r '
  .quota // empty
  | if type == "object" then
      to_entries
      | map(select(.value.remaining_fraction != null))
      | sort_by(.value.remaining_fraction)
      | .[0] // empty
      | "\(.key)\t\(.value.remaining_fraction * 100 | round)"
    else
      empty
    end
' 2>/dev/null || true)

status=""
if [ -n "$model" ]; then
  status=$(printf "\033[0;36m%s\033[00m" "$model")
fi

if [ -n "$used" ]; then
  pct=$(printf '%.0f' "$used" 2>/dev/null || true)
  if [ -n "$pct" ]; then
    filled=$(( pct * 10 / 100 ))
    [ "$filled" -gt 10 ] && filled=10
    [ "$filled" -lt 0 ] && filled=0
    empty=$(( 10 - filled ))
    [ "$empty" -lt 0 ] && empty=0
    bar=""
    for i in $(seq 1 $filled); do bar="${bar}█"; done
    for i in $(seq 1 $empty);  do bar="${bar}░"; done
    if [ "$pct" -ge 80 ]; then
      color="\033[0;31m"
    elif [ "$pct" -ge 50 ]; then
      color="\033[0;33m"
    else
      color="\033[0;32m"
    fi
    ctx_part=$(printf "%b%s %s%%\033[00m" "$color" "$bar" "$pct")
    if [ -n "$status" ]; then
      status="${status} | ${ctx_part}"
    else
      status="${ctx_part}"
    fi
  fi
fi

if [ -n "$quota_info" ]; then
  quota_lane=$(printf '%s' "$quota_info" | cut -f1)
  quota_pct=$(printf '%s' "$quota_info" | cut -f2)
  if [ -n "$quota_lane" ] && [ -n "$quota_pct" ]; then
    if [ "$quota_pct" -le 20 ]; then
      q_color="\033[0;31m"
    elif [ "$quota_pct" -lt 50 ]; then
      q_color="\033[0;33m"
    else
      q_color="\033[0;32m"
    fi
    quota_part=$(printf "%b%s: %s%%\033[00m" "$q_color" "$quota_lane" "$quota_pct")
    if [ -n "$status" ]; then
      status="${status} | ${quota_part}"
    else
      status="${quota_part}"
    fi
  fi
fi

printf '%b' "$status"
exit 0
