#!/bin/bash
# mage:rig/guard/release-docs-gate
# PreToolUse(Bash) hook: docs-drift release gate. Merging a release PR on a
# repo whose registry entry has a `docs` block requires a docs audit
# (rig-meta observed docs_audit_at) within the last 14 days — the rig
# docs-drift skill's Phase 1 records the marker. Fail-open everywhere.
# Escape hatch (user-approved only): DOCS_GATE=skip in the merge command.
# Rung: hook. Skipped: impossible (branch protection cannot read local audit timestamps), check (the merge command exists only at call time).
set -u
in=$(cat)
KIT_META="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/scripts/rig-meta.sh"
_lib="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/hooks/lib/report-guard.sh"
[ -f "$_lib" ] || _lib="$(cd "$(dirname "$0")" && pwd)/lib/report-guard.sh"
[ -f "$_lib" ] && . "$_lib"
type report_guard >/dev/null 2>&1 || report_guard() { :; }
cmd=$(jq -r '.tool_input.command // ""' <<<"$in" 2>/dev/null) || exit 0
grep -qE 'gh[[:space:]]+pr[[:space:]]+merge' <<<"$cmd" || exit 0
grep -q 'DOCS_GATE=skip' <<<"$cmd" && exit 0
cwd=$(jq -r '.cwd // ""' <<<"$in" 2>/dev/null)
[ -d "$cwd" ] || exit 0
cd "$cwd" || exit 0
repo=$("$KIT_META" current 2>/dev/null | jq -r '.repo // empty')
[ -n "$repo" ] || exit 0
"$KIT_META" get "$repo" docs >/dev/null 2>&1 || exit 0
pr=$(grep -oE 'merge[[:space:]]+[0-9]+' <<<"$cmd" | grep -oE '[0-9]+' | head -1)
[ -n "$pr" ] || exit 0
title=$(timeout 10 gh pr view "$pr" --repo "$repo" --json title --jq .title 2>/dev/null) || exit 0
# Anchored to the release-please title shape — a PR merely mentioning the word
# "release" must not gate.
grep -qiE '^chore(\(.+\))?: release' <<<"$title" || exit 0
now=$(date +%s); ts=$("$KIT_META" get "$repo" docs_audit_at 2>/dev/null || echo 0)
case "$ts" in ''|*[!0-9]*) ts=0;; esac
[ $((now - ts)) -lt 1209600 ] && exit 0
echo "Release gate: $repo is about to ship a release PR ('$title') with no docs audit in the last 14 days. Load the rig docs-drift skill and run Phase 1 (it records docs_audit_at via rig-meta observe), then retry the merge. If the user explicitly approved skipping the audit, include DOCS_GATE=skip in the merge command." >&2
echo "mage:rig/guard/release-docs-gate" >&2
tool=$(jq -r '.tool_name // "Bash"' <<<"$in" 2>/dev/null)
report_guard "rig/guard/release-docs-gate" "$tool" "stale docs audit: $repo"
exit 2
