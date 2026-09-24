#!/bin/bash
# agy status line, the same shape as the Claude one: model | context | each quota bucket as percent used.
# agy pipes .quota as {bucket-id: {remaining_fraction, reset_time, reset_in_seconds}}; gemini-* and 3p-*
# are the two groups. Docs: antigravity.google/docs/cli/statusline. Story: rig#133.
input=$(cat)
command -v jq >/dev/null 2>&1 || { printf 'agy'; exit 0; }

color_for() {  # percent used -> ansi color: green <50, yellow 50-79, red 80+
  if [ "$1" -ge 80 ]; then printf '\033[0;31m'; elif [ "$1" -ge 50 ]; then printf '\033[0;33m'; else printf '\033[0;32m'; fi
}

model=$(jq -r '.model.display_name // .model.id // empty' <<<"$input" 2>/dev/null)
used=$(jq -r '.context_window.used_percentage // empty' <<<"$input" 2>/dev/null)

out=""
[ -n "$model" ] && out="\033[0;36m${model}\033[00m"

if [ -n "$used" ]; then
  pct=$(printf '%.0f' "$used"); [ "$pct" -gt 100 ] && pct=100
  filled=$(( pct * 10 / 100 )); bar=""
  for i in $(seq 1 10); do [ "$i" -le "$filled" ] && bar="${bar}█" || bar="${bar}░"; done
  out="${out:+$out | }$(color_for "$pct")${bar} ${pct}%\033[00m"
fi

# One field per bucket, 5h before weekly within a group: "Gemini 5h 87% ↺152m | Gemini 7d 31%"
while IFS=$'\t' read -r label p secs; do
  [ -n "$label" ] || continue
  left=""
  case "$label" in *" 5h") [ "${secs:-0}" -gt 0 ] && left=" ↺$(( secs / 60 ))m" ;; esac
  out="${out:+$out | }${label} $(color_for "$p")${p}%\033[00m${left}"
done < <(jq -r '
  (.quota // {}) | to_entries | map(select(.value.remaining_fraction != null))
  | map({group: (if (.key | startswith("gemini")) then "Gemini" elif (.key | startswith("3p")) then "Claude/GPT" else (.key | split("-")[0]) end),
         window: (if (.key | endswith("5h")) then "5h" elif (.key | endswith("weekly")) then "7d" else (.key | split("-")[-1]) end),
         used: ((1 - .value.remaining_fraction) * 100 | round),
         secs: (.value.reset_in_seconds // 0 | floor)})
  | sort_by((.group != "Gemini"), .group, (.window != "5h"))
  | .[] | "\(.group) \(.window)\t\(.used)\t\(.secs)"' <<<"$input" 2>/dev/null)

printf '%b' "$out"
exit 0
