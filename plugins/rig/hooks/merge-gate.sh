#!/bin/bash
# PreToolUse(Bash) hook: a merge is a per-merge permission (AGENTS.md §The organizer seat). The seat
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

pr="" prefix="" api="no"
gh_re='gh\s+pr\s+merge\b'
if printf '%s' "$cmd" | gh_scan prefix "$gh_re" >/dev/null; then
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
else
  api="yes"
  gh_re='gh\s+api\b'
  prefix=$(printf '%s' "$cmd" | gh_scan prefix "$gh_re" 2>/dev/null || true)
  pr=$(grep -oE 'pulls/[0-9]+/merge' <<<"$cmd" | head -1 | grep -oE '[0-9]+' || true)
fi

# The token can sit as an env prefix on the gh call or anywhere earlier in the command.
token=$(grep -oE '(^|[;&|[:space:]])MERGE_OK=[^[:space:];&|]+' <<<"${prefix:-$cmd}" | tail -1 | sed -E 's/.*MERGE_OK=//; s/^["'"'"']//; s/["'"'"']$//')
[ -n "$token" ] || token=$(grep -oE '(^|[;&|[:space:]])MERGE_OK=[^[:space:];&|]+' <<<"$cmd" | tail -1 | sed -E 's/.*MERGE_OK=//; s/^["'"'"']//; s/["'"'"']$//')

if [ -n "$token" ]; then
  [ -z "$pr" ] && exit 0
  [ "$token" = "$pr" ] && exit 0
fi

which="PR ${pr:-<current branch>}"
[ "$api" = "yes" ] && which="pulls/${pr:-?}/merge via gh api"
cat >&2 <<MSG
Blocked by rig/guard/merge-gate: merging $which needs the operator's word for this PR (AGENTS.md §The
organizer seat: merge is a per-merge permission, never carried forward). Ask, then record it on the
same command: MERGE_OK=${pr:-<pr>} gh pr merge ${pr:-<pr>} ... The token must name this PR${token:+; it names $token}.
MSG
exit 2
