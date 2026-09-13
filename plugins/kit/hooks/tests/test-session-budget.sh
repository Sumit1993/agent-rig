#!/bin/bash
# Regression suite for session-budget.sh (SessionStart). Refs #123.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/session-budget.sh"
fails=0; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ctx() { jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

printf '{"ts":"%s","five_hour":{"used_percentage":63,"resets_at":1},"seven_day":{"used_percentage":36}}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$T/usage.jsonl"
cat > "$T/quota.sh" <<'Q'
#!/bin/bash
case "$2" in gemini*) echo "exhausted: gemini until 2026-09-11T00:00Z";; *) echo "usable: $2 has no quota record";; esac
Q
chmod +x "$T/quota.sh"

out=$(echo '{"session_id":"s"}' | BUDGET_USAGE_LOG="$T/usage.jsonl" BUDGET_QUOTA_SH="$T/quota.sh" "$HOOK" | ctx)
grep -q "5h window 63%, 7d 36%" <<<"$out" && echo "PASS: account percent from the trace" || { echo "FAIL: account ($out)"; fails=$((fails+1)); }
grep -q "agy gemini: exhausted" <<<"$out" && echo "PASS: gemini group state" || { echo "FAIL: gemini ($out)"; fails=$((fails+1)); }
grep -q "agy claude-gpt: usable" <<<"$out" && echo "PASS: claude-gpt group state" || { echo "FAIL: claude-gpt"; fails=$((fails+1)); }
grep -q "Sonnet subagents only" <<<"$out" && echo "PASS: policy line present" || { echo "FAIL: policy"; fails=$((fails+1)); }

out=$(echo '{}' | BUDGET_USAGE_LOG="$T/none.jsonl" BUDGET_QUOTA_SH="$T/missing.sh" "$HOOK" | ctx)
grep -q "no trace yet" <<<"$out" && grep -q "unknown" <<<"$out" && echo "PASS: missing trace and quota script degrade to words" || { echo "FAIL: missing inputs ($out)"; fails=$((fails+1)); }

out=$(echo '{"source":"resume","seconds_since_last_response":5400,"context_tokens":91000,"prompt_cache_likely_expired":true}' | BUDGET_USAGE_LOG="$T/usage.jsonl" BUDGET_QUOTA_SH="$T/quota.sh" "$HOOK" | ctx)
grep -q "Resumed after 90m: 91000 context tokens re-sent, prompt cache likely expired" <<<"$out" && echo "PASS: resume cost line from the SessionStart fields" || { echo "FAIL: resume ($out)"; fails=$((fails+1)); }
out=$(echo '{"source":"startup"}' | BUDGET_USAGE_LOG="$T/usage.jsonl" BUDGET_QUOTA_SH="$T/quota.sh" "$HOOK" | ctx)
grep -q "Resumed" <<<"$out" && { echo "FAIL: startup claims a resume"; fails=$((fails+1)); } || echo "PASS: a fresh start says nothing about resuming"

rc=$(printf 'junk' | BUDGET_USAGE_LOG="$T/none.jsonl" BUDGET_QUOTA_SH="$T/quota.sh" "$HOOK" >/dev/null 2>&1; echo $?)
[ "$rc" -eq 0 ] && echo "PASS: junk stdin exits 0" || { echo "FAIL: junk rc=$rc"; fails=$((fails+1)); }

[ "$fails" -eq 0 ] && echo "all session-budget hook tests passed"; exit "$fails"
