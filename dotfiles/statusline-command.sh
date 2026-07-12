#!/bin/bash
input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
model=$(echo "$input" | jq -r '.model.display_name // empty')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# PS1-based portion: bold green user@host, reset, colon, bold blue cwd, reset
prompt=$(printf "\033[01;32m%s@%s\033[00m:\033[01;34m%s\033[00m" "$(whoami)" "$(hostname -s)" "$cwd")

# Build extras
extra=""

# Model name
[ -n "$model" ] && extra=" | \033[0;36m${model}\033[00m"

# Context progress bar (10 blocks wide)
if [ -n "$used" ]; then
  pct=$(printf '%.0f' "$used")
  filled=$(( pct * 10 / 100 ))
  empty=$(( 10 - filled ))
  bar=""
  for i in $(seq 1 $filled); do bar="${bar}█"; done
  for i in $(seq 1 $empty);  do bar="${bar}░"; done
  # Color: green <50%, yellow 50-79%, red 80%+
  if [ "$pct" -ge 80 ]; then
    color="\033[0;31m"
  elif [ "$pct" -ge 50 ]; then
    color="\033[0;33m"
  else
    color="\033[0;32m"
  fi
  extra="${extra} | ${color}${bar} ${pct}%\033[00m"
fi

printf '%b' "${prompt}${extra}"
