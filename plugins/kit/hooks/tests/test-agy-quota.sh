#!/bin/bash
# Regression suite for agy-quota.sh and watchdog quota recording. Refs #108, #107.
set -u
SRC="$(cd "$(dirname "$0")/../../skills/agy-delegate" && pwd)"
AGY_QUOTA="$SRC/agy-quota.sh"
WATCHDOG="$SRC/run-agy-watchdog.sh"
fails=0

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

export XDG_STATE_HOME="$TMPDIR/state"
mkdir -p "$TMPDIR/bin" "$TMPDIR/wt" "$TMPDIR/state"

cat << 'STUB_AGY' > "$TMPDIR/bin/agy"
#!/bin/sh
if [ "$1" = "--version" ]; then echo "1.1.27"; exit 0; fi
if [ "${STUB_AGY_MODE:-}" = "quota" ]; then
  echo '{"status":"ERROR","num_turns":0,"error":"Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 1h35m27s."}'
  exit 1
fi
if [ "${STUB_AGY_MODE:-}" = "ok" ]; then
  echo '{"status":"SUCCESS","conversation_id":"c123","num_turns":1,"response":"done"}'
  exit 0
fi
exit 1
STUB_AGY
cat << 'STUB_SLEEP' > "$TMPDIR/bin/sleep"
#!/bin/sh
exit 0
STUB_SLEEP
chmod +x "$TMPDIR/bin/agy" "$TMPDIR/bin/sleep"
PATH="$TMPDIR/bin:$PATH"
export PATH

check() {
  local desc="$1" cond="$2"
  if eval "$cond"; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc"; fails=$((fails + 1))
  fi
}

echo "-- 1. The verb records a quota envelope"
cat << 'EOF' > "$TMPDIR/quota_env.json"
{"status":"ERROR","num_turns":0,"error":"Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 1h35m27s."}
EOF
c1_out=$(bash "$AGY_QUOTA" record-from-envelope gemini-3.8-flash-high "$TMPDIR/quota_env.json" 2>&1) || true
c1_chk_rc=0
c1_chk_out=$(bash "$AGY_QUOTA" check gemini-3.8-flash-high 2>&1) || c1_chk_rc=$?
c1_rec_pass=0
case "$c1_out" in
  recorded:*) c1_rec_pass=1 ;;
  *) c1_rec_pass=0 ;;
esac
c1_chk_pass=0
case "$c1_chk_out" in
  exhausted:*) c1_chk_pass=1 ;;
  *) c1_chk_pass=0 ;;
esac
check "the verb records a quota envelope" '[ "$c1_rec_pass" -eq 1 ] && [ "$c1_chk_rc" -eq 1 ] && [ "$c1_chk_pass" -eq 1 ]'

echo "-- 2. The reset duration is parsed, not dropped"
c2_reset_at=$(jq -r '.["gemini-3.8-flash-high"].reset_at // empty' "$TMPDIR/state/agy/quota.json" 2>/dev/null || echo "")
c2_date_ok=0
if [ -n "$c2_reset_at" ] && [ "$c2_reset_at" != "null" ]; then
  date -u -d "$c2_reset_at" +%s >/dev/null 2>&1 && c2_date_ok=1
fi
c2_rem=$(echo "$c1_chk_out" | sed -n 's/.*(\([0-9]\+\)s remaining).*/\1/p')
check "the reset duration is parsed and remaining seconds are roughly 1h35m" '[ -n "$c2_reset_at" ] && [ "$c2_date_ok" -eq 1 ] && [ -n "$c2_rem" ] && [ "$c2_rem" -ge 5000 ] && [ "$c2_rem" -le 5800 ]'

echo "-- 3. A healthy envelope records nothing"
bash "$AGY_QUOTA" clear gemini-3.8-flash-high
echo '{"status":"SUCCESS","num_turns":1,"response":"ok"}' > "$TMPDIR/healthy_env.json"
c3_rec_rc=0
c3_rec_out=$(bash "$AGY_QUOTA" record-from-envelope gemini-3.8-flash-high "$TMPDIR/healthy_env.json" 2>&1) || c3_rec_rc=$?
c3_chk_rc=0
c3_chk_out=$(bash "$AGY_QUOTA" check gemini-3.8-flash-high 2>&1) || c3_chk_rc=$?
c3_no_rec=0
case "$c3_rec_out" in
  *recorded:*) c3_no_rec=0 ;;
  *) c3_no_rec=1 ;;
esac
c3_usable=0
case "$c3_chk_out" in
  usable:*) c3_usable=1 ;;
  *) c3_usable=0 ;;
esac
check "a healthy envelope records nothing" '[ "$c3_rec_rc" -eq 0 ] && [ "$c3_no_rec" -eq 1 ] && [ "$c3_chk_rc" -eq 0 ] && [ "$c3_usable" -eq 1 ]'

echo "-- 4. A non-quota error records nothing"
bash "$AGY_QUOTA" clear gemini-3.8-flash-high
echo '{"status":"ERROR","error":"connection reset by peer"}' > "$TMPDIR/nonquota_env.json"
c4_rec_rc=0
c4_rec_out=$(bash "$AGY_QUOTA" record-from-envelope gemini-3.8-flash-high "$TMPDIR/nonquota_env.json" 2>&1) || c4_rec_rc=$?
c4_chk_rc=0
c4_chk_out=$(bash "$AGY_QUOTA" check gemini-3.8-flash-high 2>&1) || c4_chk_rc=$?
c4_no_rec=0
case "$c4_rec_out" in
  *recorded:*) c4_no_rec=0 ;;
  *) c4_no_rec=1 ;;
esac
c4_usable=0
case "$c4_chk_out" in
  usable:*) c4_usable=1 ;;
  *) c4_usable=0 ;;
esac
check "a non-quota error records nothing" '[ "$c4_rec_rc" -eq 0 ] && [ "$c4_no_rec" -eq 1 ] && [ "$c4_chk_rc" -eq 0 ] && [ "$c4_usable" -eq 1 ]'

echo "-- 5. A missing envelope is loud, not silent"
c5_rc=0
c5_stderr=$(bash "$AGY_QUOTA" record-from-envelope gemini-3.8-flash-high "$TMPDIR/does-not-exist.json" 2>&1 >/dev/null) || c5_rc=$?
c5_match=0
case "$c5_stderr" in
  *no\ envelope*) c5_match=1 ;;
  *) c5_match=0 ;;
esac
check "a missing envelope is loud, not silent" '[ "$c5_rc" -eq 3 ] && [ "$c5_match" -eq 1 ]'

echo "-- 6. The watchdog path learns"
bash "$AGY_QUOTA" clear quota-model
echo "test prompt" > "$TMPDIR/prompt.md"
STUB_AGY_MODE=quota bash "$WATCHDOG" "$TMPDIR/wt" "$TMPDIR/prompt.md" "$TMPDIR/out_wd.json" 0 10s quota-model >/dev/null 2>&1 || true
c6_chk_rc=0
bash "$AGY_QUOTA" check quota-model >/dev/null 2>&1 || c6_chk_rc=$?
c6_sidecar_quota=$(jq -r '.quota_exhausted // false' "$TMPDIR/out_wd.json.meta.json" 2>/dev/null || echo false)
c6_delegates=0
grep -q 'record-from-envelope' "$WATCHDOG" && c6_delegates=1
check "the watchdog path learns" '[ "$c6_chk_rc" -eq 1 ] && [ "$c6_sidecar_quota" = "true" ] && [ "$c6_delegates" -eq 1 ]'

echo "-- 7. The bare-sentinel path learns when it calls the verb"
bash "$AGY_QUOTA" clear bare-model
cat << 'EOF' > "$TMPDIR/bare_out.json"
{"status":"ERROR","num_turns":0,"error":"Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 1h35m27s."}
EOF
c7_pre_chk_rc=0
c7_pre_out=$(bash "$AGY_QUOTA" check bare-model 2>&1) || c7_pre_chk_rc=$?
c7_pre_usable=0
case "$c7_pre_out" in
  usable:*) c7_pre_usable=1 ;;
  *) c7_pre_usable=0 ;;
esac
bash "$AGY_QUOTA" record-from-envelope bare-model "$TMPDIR/bare_out.json" >/dev/null 2>&1
c7_post_chk_rc=0
c7_post_out=$(bash "$AGY_QUOTA" check bare-model 2>&1) || c7_post_chk_rc=$?
c7_post_exhausted=0
case "$c7_post_out" in
  exhausted:*) c7_post_exhausted=1 ;;
  *) c7_post_exhausted=0 ;;
esac
check "the bare-sentinel path learns when it calls the verb" '[ "$c7_pre_chk_rc" -eq 0 ] && [ "$c7_pre_usable" -eq 1 ] && [ "$c7_post_chk_rc" -eq 1 ] && [ "$c7_post_exhausted" -eq 1 ]'

echo "-- 8. The usage line names the new verb"
c8_rc=0
c8_err=$(bash "$AGY_QUOTA" 2>&1) || c8_rc=$?
c8_match=0
case "$c8_err" in
  *record-from-envelope*) c8_match=1 ;;
  *) c8_match=0 ;;
esac
check "the usage line names the new verb" '[ "$c8_rc" -eq 2 ] && [ "$c8_match" -eq 1 ]'

[ "$fails" -eq 0 ] && echo && echo "all test-agy-quota tests passed"
exit "$fails"
