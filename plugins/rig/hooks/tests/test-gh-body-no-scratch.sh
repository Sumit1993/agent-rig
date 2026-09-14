#!/bin/bash
# Regression suite for gh-body-no-scratch.sh (PreToolUse Bash). Refs #123.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/gh-body-no-scratch.sh"
fails=0
CWD=$(mktemp -d)
TMPDIR_TEST=$(mktemp -d)
cleanup() { rm -rf "$CWD" "$TMPDIR_TEST"; }
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

echo "contains /tmp/claude-1000" > "$TMPDIR_TEST/dirty-file.txt"
echo "clean report" > "$TMPDIR_TEST/clean-file.txt"

check "inline body see ~/ai-context/x.md blocks" 2 'gh issue create --title "Issue" --body "see ~/ai-context/x.md"'

heredoc_cmd=$(cat <<'BODYEOF'
gh issue create --title "Heredoc" --body-file - <<'BODY'
report in /tmp/claude-1000/report.md
BODY
BODYEOF
)
check "heredoc with /tmp/ blocks" 2 "$heredoc_cmd"

check "body-file with dirty content blocks" 2 "gh issue create --title \"Dirty\" --body-file \"$TMPDIR_TEST/dirty-file.txt\""
check "body-file with clean content under mktemp path passes" 0 "gh issue create --title \"Clean\" --body-file \"$TMPDIR_TEST/clean-file.txt\""
check "clean inline body passes" 0 'gh issue create --title "Clean" --body "clean body"'
check "SCRATCH_GATE=skip with dirty body passes" 0 'SCRATCH_GATE=skip gh issue create --title "Skip" --body "see ~/ai-context/x.md"'
check "git commit -m ai-context passes" 0 'git commit -m "ai-context"'

# Misfires seen 2026-09-13/14 (#136, #123): a scratch path elsewhere in the Bash call, not in the body.
check "scratch path in a command before gh, clean body file, passes" 0 \
  "sed 's/a/b/' /tmp/claude-1000/src.md > \"$TMPDIR_TEST/clean-file.txt\"; gh issue comment 5 --body-file \"$TMPDIR_TEST/clean-file.txt\""
check "scratch path in a command after gh passes" 0 \
  "gh issue comment 5 --body-file \"$TMPDIR_TEST/clean-file.txt\" && echo done >> ~/ai-context/plan.md"
check "body file named through a variable is read, clean passes" 0 \
  "B=\"$TMPDIR_TEST/clean-file.txt\"; gh pr edit 5 --body-file \$B"
check "body file named through a variable is read, dirty blocks" 2 \
  "B=\"$TMPDIR_TEST/dirty-file.txt\"; gh pr edit 5 --body-file \"\$B\""
check "inline body is still read to the end of the call" 2 \
  'gh pr comment 5 --body "line one; see /tmp/claude-1000/x.md"'
# CodeRabbit on #137: quoted gh text earlier in the call, and a reassignment after gh.
check "a quoted gh command in an earlier argument is not the gh call" 0 \
  "printf '%s' 'gh issue create --body \"see ~/ai-context/x.md\"'; gh issue comment 5 --body \"clean body\""
check "a reassignment after gh does not change the file read" 2 \
  "B=\"$TMPDIR_TEST/dirty-file.txt\"; gh issue comment 5 --body-file \"\$B\"; B=\"$TMPDIR_TEST/clean-file.txt\""
check "gh issue view passes" 0 'gh issue view 5'

[ "$fails" -eq 0 ] && echo && echo "all gh-body-no-scratch hook tests passed"
exit "$fails"
