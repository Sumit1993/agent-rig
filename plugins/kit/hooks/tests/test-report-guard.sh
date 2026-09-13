#!/bin/bash
# Regression suite for report-guard.sh (fire-and-forget mage observe reporter).
# Sourced by hooks when blocking to report guard_id, tool, and detail.
set -u
LIB="$(cd "$(dirname "$0")/.." && pwd)/lib/report-guard.sh"
fails=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; fails=$((fails + 1)); }

[ -f "$LIB" ] || { echo "FAIL: library not found at $LIB"; exit 1; }
. "$LIB"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 1. report_guard returns 0 when mage is absent from PATH
rc=0
out=$(PATH=/usr/bin:/bin report_guard "kit/guard/test-absent" "Agent" "detail" 2>&1) || rc=$?
if [ "$rc" -eq 0 ]; then
  pass "report_guard returns 0 when mage is absent from PATH"
else
  fail "report_guard failed with rc=$rc when mage is absent from PATH"
fi

# 2. report_guard returns 0 when mage exists and fails. Stub a failing mage on PATH.
mkdir -p "$TMP/bin-failing"
cat > "$TMP/bin-failing/mage" <<'EOF'
#!/bin/bash
echo "mage error" >&2
exit 1
EOF
chmod +x "$TMP/bin-failing/mage"

rc=0
out=$(PATH="$TMP/bin-failing:/usr/bin:/bin" report_guard "kit/guard/test-fail" "Bash" "failing mage" 2>&1) || rc=$?
if [ "$rc" -eq 0 ]; then
  pass "report_guard returns 0 when mage exists and fails"
else
  fail "report_guard failed with rc=$rc when mage exists and fails"
fi

# 3. It writes nothing to stdout. Assert stdout is empty, not merely that it looks right.
mkdir -p "$TMP/bin-verbose"
cat > "$TMP/bin-verbose/mage" <<'EOF'
#!/bin/bash
echo "leaked output"
exit 0
EOF
chmod +x "$TMP/bin-verbose/mage"

stdout_capture="$TMP/stdout.txt"
PATH="$TMP/bin-verbose:/usr/bin:/bin" report_guard "kit/guard/test-stdout" "Agent" "check stdout" > "$stdout_capture"
if [ ! -s "$stdout_capture" ]; then
  pass "report_guard writes nothing to stdout"
else
  fail "report_guard wrote to stdout: $(cat "$stdout_capture")"
fi

# 4. The JSON it sends is valid and carries the three fields. Stub mage with a script
# that captures stdin to a file, then assert on that file with jq.
mkdir -p "$TMP/bin-capture"
captured="$TMP/captured.json"
cat > "$TMP/bin-capture/mage" <<EOF
#!/bin/bash
cat > "$captured"
exit 0
EOF
chmod +x "$TMP/bin-capture/mage"

rm -f "$captured"
PATH="$TMP/bin-capture:/usr/bin:/bin" report_guard "kit/guard/test-fields" "Write" "valid reason"
if [ -f "$captured" ] && jq -e '.guard_id == "kit/guard/test-fields" and .tool == "Write" and .detail == "valid reason"' "$captured" >/dev/null 2>&1; then
  pass "the JSON it sends is valid and carries the three fields"
else
  fail "captured JSON invalid or missing fields: $(cat "$captured" 2>/dev/null || echo '<no file>')"
fi

# 5. A detail containing a double quote and a newline still produces valid JSON.
rm -f "$captured"
complex_detail=$(printf 'has "quotes" and\nnew lines in it')
PATH="$TMP/bin-capture:/usr/bin:/bin" report_guard "kit/guard/test-escape" "Edit" "$complex_detail"
if [ -f "$captured" ] && jq -e --arg want "$complex_detail" '.guard_id == "kit/guard/test-escape" and .tool == "Edit" and .detail == $want' "$captured" >/dev/null 2>&1; then
  pass "a detail containing a double quote and a newline still produces valid JSON"
else
  fail "captured JSON with quotes/newlines invalid: $(cat "$captured" 2>/dev/null || echo '<no file>')"
fi

[ "$fails" -eq 0 ] && echo && echo "all report-guard tests passed"
exit "$fails"
