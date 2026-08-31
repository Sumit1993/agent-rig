#!/bin/bash
# Run every hook/script suite in this directory. Used by CI and by hand.
# Globs rather than listing, so a new suite is picked up by existing it.
set -u
cd "$(dirname "$0")" || exit 1
fails=0

for t in test-*.sh check-*.sh replay-*.sh; do
  [ -e "$t" ] || continue
  echo "=== $t"
  if timeout 300 bash "$t"; then
    echo
  else
    echo ">>> $t FAILED (rc=$?)"; echo
    fails=$((fails + 1))
  fi
done

if [ "$fails" -eq 0 ]; then
  echo "all suites passed"
  exit 0
fi
echo "$fails suite(s) failed"
exit 1
