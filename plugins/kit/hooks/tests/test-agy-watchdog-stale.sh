#!/bin/bash
# Regression suite for run-agy-watchdog.sh's fmt_stale(), extracted the same way
# test-retry-seconds.sh drives watch-coderabbit.sh's retry_seconds(): sourced without
# running the rest of the script (which launches agy and needs a real worktree). Refs #82.
set -u
SRC="$(cd "$(dirname "$0")/../../skills/agy-delegate" && pwd)/run-agy-watchdog.sh"
fails=0
bash -n "$SRC" || { echo "FAIL: run-agy-watchdog.sh has a syntax error"; exit 1; }
echo "PASS: run-agy-watchdog.sh syntax ok"

fn=$(mktemp); sed -n '/^fmt_stale()/,/^}$/p' "$SRC" > "$fn"
trap 'rm -f "$fn"' EXIT
[ -s "$fn" ] || { echo "FAIL: fmt_stale() not found in $SRC"; exit 1; }

check() { # name seconds want
  local name=$1 secs=$2 want=$3 out
  out=$(bash -c 'set -u; source "$1"; fmt_stale "$2"' _ "$fn" "$secs")
  if [ "$out" = "$want" ]; then
    echo "PASS: $name"
  else
    echo "FAIL: $name (want $want, got $out)"; fails=$((fails + 1))
  fi
}

check "3 minutes 12 seconds" 192 "3m12s"
check "exactly one minute" 60 "1m0s"
check "under a minute" 45 "0m45s"
check "zero" 0 "0m0s"
check "over an hour still m/s (watchdog kills well under an hour)" 3661 "61m1s"

[ "$fails" -eq 0 ] && { echo; echo "all agy-watchdog staleness tests passed"; exit 0; }
echo "$fails failure(s)"; exit 1
