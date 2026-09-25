#!/bin/bash
# mage:rig/guard/summon-gate
# PreToolUse(Bash) hook: the hourly CodeRabbit routine is the only summoner; a session summons only on the
# operator's word, recorded as CR_SUMMON_OK=<pr> on the same command. One review per developer per hour
# across every repo, so a hand summon starves the routine's pick (Sumit1993/rig#150).
set -u
in=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$in" 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0
grep -qiE '@coderabbit(ai)?[[:space:]]+(full[[:space:]]+)?review\b|@coderabbit(ai)?[[:space:]]+review[[:space:]]+full\b' <<<"$cmd" || exit 0
# A post, not a read: gh pr/issue comment, or gh api .../comments carrying a body field.
grep -qE 'gh[[:space:]]+(pr|issue)[[:space:]]+comment\b' <<<"$cmd" \
  || { grep -qE 'issues/[0-9]+/comments' <<<"$cmd" && grep -qE '(-f|-F|--field|--raw-field)[[:space:]]+body=|--input\b' <<<"$cmd"; } \
  || exit 0

pr=$(grep -oE 'gh[[:space:]]+(pr|issue)[[:space:]]+comment[[:space:]]+[0-9]+|issues/[0-9]+/comments' <<<"$cmd" | grep -oE '[0-9]+' | head -1)
token=$(grep -oE '(^|[;&|[:space:]])CR_SUMMON_OK=[^[:space:];&|]+' <<<"$cmd" | tail -1 | sed -E 's/.*CR_SUMMON_OK=//; s/^["'"'"']//; s/["'"'"']$//')
[ -n "$token" ] && [ -n "$pr" ] && [ "$token" = "$pr" ] && exit 0

cat >&2 <<MSG
Blocked by rig/guard/summon-gate: the hourly CodeRabbit routine summons reviews, not sessions (Sumit1993/rig#150).
CodeRabbit allows one review per developer per hour across every repo, so a hand summon takes the routine's slot.
Instead: fix, push once, reply in every thread with cr-reply.sh, and stop; the routine re-reviews a PR whose
CodeRabbit threads all carry a reply. Never use \`full review\` as a retry: the "does not re-review already reviewed
commits" line is a footer on every reply. If the operator asks for a summon on this PR, record it on the same
command: CR_SUMMON_OK=${pr:-<pr>} gh pr comment ${pr:-<pr>} --body \$'@coderabbitai review\n\n<!-- summoned-by: session -->'${token:+ (the token names $token)}
MSG
exit 2
