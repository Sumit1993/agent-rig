#!/bin/bash
# Run every hook/script suite in this directory. Used by CI and by hand.
# Globs rather than listing, so a new suite is picked up by existing it.
set -u
cd "$(dirname "$0")" || exit 1
fails=0
timeouts=0

for t in test-*.sh check-*.sh replay-*.sh; do
  [ -e "$t" ] || continue
  echo "=== $t"
  # A full replay (REPLAY_LIMIT=0) runs ~342s; every other suite stays at 300s.
  cap=300
  case "$t" in
    replay-*.sh) [ "${REPLAY_LIMIT:-400}" = "0" ] && cap=900 ;;
  esac
  timeout "$cap" bash "$t"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo
  elif [ "$rc" -eq 124 ]; then
    echo ">>> $t TIMED OUT after ${cap}s (rc=124)"; echo
    timeouts=$((timeouts + 1))
  else
    echo ">>> $t FAILED (rc=$rc)"; echo
    fails=$((fails + 1))
  fi
done

if [ "$fails" -eq 0 ] && [ "$timeouts" -eq 0 ]; then
  echo "all suites passed"
  exit 0
fi
echo "$fails suite(s) failed, $timeouts timed out"
exit 1
