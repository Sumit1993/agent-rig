#!/bin/bash
# Regression suite for watch-coderabbit.sh's retry_seconds().
# Fixtures are REAL CodeRabbit notice bodies pulled from prismalens/gh-workflows PRs.
# The parser once matched only the colon wording and silently fell back to 60m for a
# month while notices said 6 to 30 minutes; these hold it to the wordings in the wild.
# The figure is now obeyed rather than floored: it measures within 15 seconds of the real
# per-developer window. The fallback covers only a notice with no figure in it. See claude-kit#28.
set -u
SRC="$(cd "$(dirname "$0")/../../skills/pr-babysit" && pwd)/watch-coderabbit.sh"
fails=0
fn=$(mktemp); sed -n '/^COOLDOWN_SECONDS=/,/^}$/p' "$SRC" > "$fn"
trap 'rm -f "$fn"' EXIT

check() { # name expected_secs expected_notice body [cooldown]
  local name=$1 want=$2 wantn=$3 body=$4 cd=${5:-}
  local out
  out=$(CR_WATCH_COOLDOWN_SECONDS="$cd" bash -c '
    set -u; source "$1"; retry_seconds "$2"; echo "$RETRY_SECS|$RETRY_NOTICE"' _ "$fn" "$body" 2>&1)
  if [ "$out" = "$want|$wantn" ]; then
    echo "PASS: $name"
  else
    echo "FAIL: $name (want $want|$wantn, got $out)"; fails=$((fails + 1))
  fi
}

echo "-- real notice wordings are obeyed, not floored"
check "included, no colon"     1800 1800 '> **Next included review available in 30 minutes.**'
check "will be available"      1380 1380 'Your next included review will be available in 23 minutes.'
check "older colon form"       2820 2820 'Next review available in: **47 minutes**'
check "six minutes"            360  360  'Your next included review will be available in 6 minutes.'
echo "-- hours parse as hours"
check "two hours"              7200 7200 'Next review available in: **2 hours**'
echo "-- the fallback is only for a notice with no figure in it"
check "unparseable falls back" 3600 ''   'Review rate limited. Nothing numeric here.'
echo "-- CR_WATCH_COOLDOWN_SECONDS is the fallback, and never overrides a parsed figure"
check "a parsed figure ignores the fallback entirely" 1800 1800 '> **Next included review available in 30 minutes.**' 9999
check "junk value cannot crash the poller" 3600 '' 'Review rate limited. Nothing numeric here.' abc
check "junk fallback reverts to 3600, parsed figure still wins" 1800 1800 '> **Next included review available in 30 minutes.**' abc
check "the fallback is used when it is set and nothing parses" 2340 '' 'Review rate limited. Nothing numeric here.' 2340

[ "$fails" -eq 0 ] && echo && echo "all retry_seconds tests passed"
exit "$fails"
