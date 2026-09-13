#!/bin/bash
# Reads the statusline JSON Claude Code pipes in. rate_limits arrives on v2.1.251+ for
# Pro and Max after the first API response; each render is also appended to
# ~/.claude/metrics/usage.jsonl so a window that fills up has a local trace. Story: claude-kit#124.
input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
model=$(echo "$input" | jq -r '.model.display_name // empty')
used=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')

# PS1-based portion: bold green user@host, reset, colon, bold blue cwd, reset
prompt=$(printf "\033[01;32m%s@%s\033[00m:\033[01;34m%s\033[00m" "$(whoami)" "$(hostname -s)" "$cwd")

extra=""
[ -n "$model" ] && extra=" | \033[0;36m${model}\033[00m"

color_for() {  # percent -> ansi color: green <50, yellow 50-79, red 80+
  if [ "$1" -ge 80 ]; then printf '\033[0;31m'; elif [ "$1" -ge 50 ]; then printf '\033[0;33m'; else printf '\033[0;32m'; fi
}

# Context progress bar (10 blocks wide)
if [ -n "$used" ]; then
  pct=$(printf '%.0f' "$used")
  filled=$(( pct * 10 / 100 )); empty=$(( 10 - filled ))
  bar=""
  for i in $(seq 1 $filled); do bar="${bar}█"; done
  for i in $(seq 1 $empty);  do bar="${bar}░"; done
  extra="${extra} | $(color_for $pct)${bar} ${pct}%\033[00m"
fi

# Account windows: 5h and 7d percent, plus minutes until the 5h window resets
if [ -n "$five" ]; then
  f=$(printf '%.0f' "$five"); w=$(printf '%.0f' "${week:-0}")
  left=""
  if [ -n "$five_reset" ]; then
    case "$five_reset" in *[!0-9]*) reset_epoch=$(date -d "$five_reset" +%s 2>/dev/null || echo 0) ;; *) reset_epoch=$five_reset ;; esac
    secs=$(( reset_epoch - $(date +%s) ))
    [ "$secs" -gt 0 ] && left=" ↺$(( secs / 60 ))m"
  fi
  extra="${extra} | 5h $(color_for $f)${f}%\033[00m${left} | 7d $(color_for $w)${w}%\033[00m"
fi

# Per-model weekly caps (Fable) are not in the stdin payload. /api/oauth/usage has them; refresh a
# cache in the background at most every 5 minutes and render from the cache. Undocumented, so any
# failure just leaves the field off. Story: claude-kit#133.
api=~/.claude/metrics/usage-api.json
if [ -z "$(find "$api" -mmin -5 2>/dev/null)" ]; then
  mkdir -p ~/.claude/metrics; touch "$api"
  ( tok=$(jq -r '.claudeAiOauth.accessToken // empty' ~/.claude/.credentials.json 2>/dev/null)
    [ -n "$tok" ] && curl -sf --max-time 8 https://api.anthropic.com/api/oauth/usage \
      -H "Authorization: Bearer $tok" -H "anthropic-beta: oauth-2025-04-20" -o "$api.tmp" \
      && jq -e '.limits' "$api.tmp" >/dev/null 2>&1 && mv "$api.tmp" "$api" ) >/dev/null 2>&1 &
fi
scoped=$(jq -c '[.limits[]? | select(.kind == "weekly_scoped") | {model: .scope.model.display_name, percent, severity, resets_at}]' "$api" 2>/dev/null)
while IFS=$'\t' read -r name p; do
  [ -n "$name" ] && extra="${extra} | ${name} $(color_for "$p")${p}%\033[00m"
done < <(jq -r '.[] | "\(.model)\t\(.percent)"' <<<"${scoped:-[]}" 2>/dev/null)

printf '%b' "${prompt}${extra}"

# Trace: one line per change of any tracked value, only when the account fields are present
if [ -n "$five" ]; then
  log=~/.claude/metrics/usage.jsonl; mkdir -p ~/.claude/metrics
  row=$(echo "$input" | jq -c --argjson scoped "${scoped:-[]}" '{session:.session_id, model:.model.id, ctx_pct:(.context_window.used_percentage|floor),
      cost_usd:.cost.total_cost_usd, five_hour:.rate_limits.five_hour, seven_day:.rate_limits.seven_day, scoped:$scoped}')
  prev=$(tail -n 1 "$log" 2>/dev/null | jq -c 'del(.ts)' 2>/dev/null)
  [ "$row" != "$prev" ] && echo "$row" | jq -c --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{ts:$ts} + .' >> "$log"
fi
