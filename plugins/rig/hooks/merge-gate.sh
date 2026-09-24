#!/bin/bash
# mage:rig/guard/merge-gate
# PreToolUse(Bash) hook: a merge is a per-merge permission (AGENTS.md §Reporting and merging). The session
# records the operator's word as MERGE_OK=<pr> on the same command; the token names one PR and never
# carries forward. Covers gh pr merge (incl. --auto) and gh api .../pulls/<n>/merge.
# Refs #123, #20. Rung: hook. Skipped: impossible (a ruleset needing one approval is stronger; open on #20 per repo).
set -u
in=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$in" 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0
grep -qE 'gh[[:space:]]+pr[[:space:]]+merge\b|pulls/[0-9]+/merge' <<<"$cmd" || exit 0

_lib="$(cd "$(dirname "$0")" && pwd)/lib/gh-command.sh"
[ -f "$_lib" ] || exit 0
. "$_lib"

_report_lib="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/hooks/lib/report-guard.sh"
[ -f "$_report_lib" ] || _report_lib="$(cd "$(dirname "$0")" && pwd)/lib/report-guard.sh"
[ -f "$_report_lib" ] && . "$_report_lib"
type report_guard >/dev/null 2>&1 || report_guard() { :; }

pr="" prefix="" api="no"
gh_re='gh\s+pr\s+merge\b'
if printf '%s' "$cmd" | gh_scan prefix "$gh_re" >/dev/null 2>&1; then
  prefix=$(printf '%s' "$cmd" | gh_scan prefix "$gh_re")
  words=()
  while IFS= read -r -d '' w; do words+=("$w"); done < <(printf '%s' "$cmd" | gh_scan words "$gh_re")
  for ((i = 3; i < ${#words[@]}; i++)); do
    w=${words[i]}
    case "$w" in
      [0-9]*) [[ "$w" =~ ^[0-9]+$ ]] && pr=$w ;;
      https://github.com/*/pull/*) pr=${w##*/pull/}; pr=${pr%%[!0-9]*} ;;
    esac
  done
elif printf '%s' "$cmd" | gh_scan prefix 'gh\s+api\b' >/dev/null 2>&1; then
  gh_re='gh\s+api\b'
  words=()
  while IFS= read -r -d '' w; do words+=("$w"); done < <(printf '%s' "$cmd" | gh_scan words "$gh_re")
  for w in "${words[@]}"; do
    if [[ "$w" =~ pulls/([0-9]+)/merge ]]; then
      pr="${BASH_REMATCH[1]}"
      api="yes"
      prefix=$(printf '%s' "$cmd" | gh_scan prefix "$gh_re")
      break
    fi
  done
  [ "$api" = "yes" ] || exit 0
else
  exit 0
fi

# The token can sit as an env prefix on the gh call or anywhere earlier in the command.
token=$(grep -oE '(^|[;&|[:space:]])MERGE_OK=[^[:space:];&|]+' <<<"${prefix:-$cmd}" | tail -1 | sed -E 's/.*MERGE_OK=//; s/^["'"'"']//; s/["'"'"']$//')
[ -n "$token" ] || token=$(grep -oE '(^|[;&|[:space:]])MERGE_OK=[^[:space:];&|]+' <<<"$cmd" | tail -1 | sed -E 's/.*MERGE_OK=//; s/^["'"'"']//; s/["'"'"']$//')

# A merge that names no PR is blocked even with a token: the token must name the PR it merges.
[ -n "$token" ] && [ -n "$pr" ] && [ "$token" = "$pr" ] && exit 0

which="PR ${pr:-<current branch>}"
[ "$api" = "yes" ] && which="pulls/${pr:-?}/merge via gh api"
cat >&2 <<MSG
Blocked by rig/guard/merge-gate: merging $which needs the operator's word for this PR (AGENTS.md §Reporting and
merging: merge is a per-merge permission, never carried forward). Ask, then record it on the
same command: MERGE_OK=${pr:-<pr>} gh pr merge ${pr:-<pr>} ... The token must name this PR${token:+; it names $token}.
MSG
report_guard "rig/guard/merge-gate" "Bash" "pr ${pr:-current}"
exit 2
