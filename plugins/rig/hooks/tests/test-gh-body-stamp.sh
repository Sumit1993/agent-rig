#!/bin/bash
# Regression suite for gh-body-stamp.sh (PreToolUse Bash). Refs #116.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/gh-body-stamp.sh"
fails=0
CWD=$(mktemp -d)
cleanup() { rm -rf "$CWD"; }
trap cleanup EXIT

check() { # name want_rc command_str
  local name=$1 want=$2 cmd=$3 got
  jq -n --arg cwd "$CWD" --arg cmd "$cmd" '{"cwd": $cwd, "tool_input": {"command": $cmd}}' | "$HOOK" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    echo "PASS: $name"
  else
    echo "FAIL: $name (want rc=$want, got rc=$got)"; fails=$((fails + 1))
  fi
}

got=$(printf 'not json' | "$HOOK" >/dev/null 2>&1; echo $?)
case "$got" in
  0|2) echo "PASS: junk stdin exits $got" ;;
  *) echo "FAIL: junk stdin rc=$got"; fails=$((fails + 1)) ;;
esac

check "gh repo view (non-covered command) passes" 0 'gh repo view'

check "inline body without marker blocks" 2 \
  'gh issue create --title "X" --body "this is a long enough body without the marker in it at all"'

check "inline body with marker passes" 0 \
  "gh issue create --title X --body \"this is a long enough body. Posted by an agent under the operator's account.\""

check "gh pr comment inline body without marker blocks" 2 \
  'gh pr comment 5 --body "this is a long enough body text with no marker present anywhere"'

BODYFILE_NO="$CWD/no-marker.txt"
echo "this is a body file long enough to matter with no marker at all in it" > "$BODYFILE_NO"
check "body-file path without marker blocks" 2 "gh issue edit 5 --body-file \"$BODYFILE_NO\""

BODYFILE_YES="$CWD/marker.txt"
printf "this is a body file long enough to matter.\nPosted by an agent under the operator's account.\n" > "$BODYFILE_YES"
check "body-file path with marker passes" 0 "gh issue edit 5 --body-file \"$BODYFILE_YES\""

heredoc_cmd=$(cat <<'CMDEOF'
gh issue comment 5 --body-file - <<'BODY'
this is a body long enough to matter, sent through a heredoc.
Posted by an agent under the operator's account.
BODY
CMDEOF
)
check "heredoc via --body-file - with marker passes" 0 "$heredoc_cmd"

heredoc_cmd_no=$(cat <<'CMDEOF'
gh issue comment 5 --body-file - <<'BODY'
this is a body long enough to matter, sent through a heredoc, no marker.
BODY
CMDEOF
)
check "heredoc via --body-file - without marker blocks" 2 "$heredoc_cmd_no"

check "short body passes" 0 'gh issue comment 5 --body "too short"'

# Misfires seen 2026-09-13/14 (#136, #123).
subst_cmd=$(cat <<'CMDEOF'
gh pr create --title X --body "$(cat <<'EOF'
The loader prints `unknown keys "description"` and ignores them, a long body.

Posted by an agent under the operator's account.
EOF
)"
CMDEOF
)
check "command-substituted heredoc with inner quotes and marker passes" 0 "$subst_cmd"

commit_then_pr=$(cat <<'CMDEOF'
git commit -q -F - <<'EOF'
fix: a commit message long enough to be read as a body by mistake
EOF
gh pr create --title X --body-file - <<'BODY'
a pull request body long enough to matter, through a heredoc.
Posted by an agent under the operator's account.
BODY
CMDEOF
)
check "git commit -F - before gh is not read as the gh body" 0 "$commit_then_pr"

check "marker with a shell-split apostrophe passes" 0 \
  "gh issue comment 5 --body 'a long enough body sent in single quotes. Posted by an agent under the operator'\\''s account.'"

unstamped_subst=$(cat <<'CMDEOF'
gh pr create --title X --body "$(cat <<'EOF'
A body with "quotes" in it and no marker, long enough to be judged.
EOF
)"
CMDEOF
)
check "command-substituted heredoc without marker still blocks" 2 "$unstamped_subst"

check "at-mention body passes" 0 'gh pr comment 5 --body "@coderabbitai review"'

check "pr create with the Claude Code footer passes" 0 \
  "gh pr create --title X --body \"this is a long enough body summary text here.

Generated with [Claude Code](https://claude.com/claude-code)\""

check "pr comment with only the Claude Code footer still blocks (footer counts for create/edit only)" 2 \
  "gh pr comment 5 --body \"this is a long enough body summary text here.

Generated with [Claude Code](https://claude.com/claude-code)\""

check "STAMP_GATE=skip passes" 0 \
  'STAMP_GATE=skip gh issue create --title X --body "this is a long enough body without the marker in it at all"'

got=$(printf '{}' | "$HOOK" >/dev/null 2>&1; echo $?)
case "$got" in
  0) echo "PASS: empty payload exits 0" ;;
  *) echo "FAIL: empty payload rc=$got (want 0)"; fails=$((fails + 1)) ;;
esac

check "non-gh command exits 0 with no output" 0 'ls -la'
out=$(jq -n --arg cwd "$CWD" --arg cmd 'ls -la' '{"cwd": $cwd, "tool_input": {"command": $cmd}}' | "$HOOK" 2>&1)
[ -z "$out" ] && echo "PASS: non-gh command prints nothing" || { echo "FAIL: non-gh command printed: $out"; fails=$((fails + 1)); }

[ "$fails" -eq 0 ] && echo && echo "all gh-body-stamp hook tests passed"
exit "$fails"
