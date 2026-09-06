#!/bin/bash
# Regression suite for reap-watchers.sh (PreToolUse start/end, --dry). Runs entirely
# inside a fresh PID+mount namespace so pgrep -f, which matches by pattern across the
# whole machine, can never see or reap a real watcher from another session. Refs #61.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/reap-watchers.sh"

if ! unshare -U --map-root-user --pid --fork --mount-proc true 2>/dev/null; then
  echo "SKIP: no unprivileged PID namespace on this host, reap-watchers left untested"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/other" "$TMP/orphan"
export TMP HOOK

for f in "$TMP/merge-cascade.sh" "$TMP/plain-worker.sh" "$TMP/other/merge-cascade.sh" \
         "$TMP/orphan/merge-cascade.sh" "$TMP/orphan/plain-worker.sh"; do
  printf '#!/bin/bash\nsleep 100\n' > "$f"; chmod +x "$f"
done

cat > "$TMP/claude" <<'EOF'
#!/bin/bash
set -u
"$TMP/merge-cascade.sh" & echo $! > "$TMP/match_own.pid"
"$TMP/plain-worker.sh" & echo $! > "$TMP/nomatch_own.pid"
sleep 0.3
printf 'junk' | "$HOOK" end --dry > "$TMP/end.out" 2>&1
echo $? > "$TMP/end.rc"
EOF
chmod +x "$TMP/claude"

cat > "$TMP/inside.sh" <<'EOF'
#!/bin/bash
set -u
"$TMP/other/merge-cascade.sh" & echo $! > "$TMP/match_other.pid"
"$TMP/claude" & echo $! > "$TMP/claude.pid"
( "$TMP/orphan/merge-cascade.sh" & echo $! > "$TMP/match_orphan.pid" )
( "$TMP/orphan/plain-worker.sh" & echo $! > "$TMP/nomatch_orphan.pid" )
for i in $(seq 1 30); do [ -f "$TMP/end.rc" ] && break; sleep 0.2; done
printf 'junk' | "$HOOK" start --dry > "$TMP/start.out" 2>&1
echo $? > "$TMP/start.rc"
EOF
chmod +x "$TMP/inside.sh"

unshare -U --map-root-user --pid --fork --mount-proc -- "$TMP/inside.sh"

fails=0
check() { # want_rc rc_file name
  if [ "$(cat "$2")" = "$1" ]; then echo "PASS: $3"; else
    echo "FAIL: $3 (rc=$(cat "$2"), want $1)"; fails=$((fails + 1)); fi
}
named() { # dry_out pidfile should name
  local hit=0
  grep -qE "would kill $(cat "$2")\$" "$1" && hit=1
  if [ "$hit" = "$3" ]; then echo "PASS: $4"; else
    echo "FAIL: $4"; fails=$((fails + 1)); fi
}

check 0 "$TMP/end.rc"   "end --dry does not crash on junk stdin"
check 0 "$TMP/start.rc" "start --dry does not crash on junk stdin"
named "$TMP/end.out"   "$TMP/match_own.pid"      1 "end: own session's matching watcher is named"
named "$TMP/end.out"   "$TMP/nomatch_own.pid"    0 "end: own session's non-matching process is not named"
named "$TMP/end.out"   "$TMP/match_other.pid"    0 "end: a different session's watcher is not named"
named "$TMP/start.out" "$TMP/match_orphan.pid"   1 "start: an orphaned matching watcher is named"
named "$TMP/start.out" "$TMP/nomatch_orphan.pid" 0 "start: an orphaned non-matching process is not named"

[ "$fails" -eq 0 ] && echo && echo "all reap-watchers hook tests passed"
exit "$fails"
