#!/bin/bash
# Regression suite for no-broad-agy-kill.sh (PreToolUse Bash).
# Blocks name-wide agy kills; leaves PID kills and run-scoped patterns alone.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/no-broad-agy-kill.sh"
fails=0

check() { # name expected_rc command
  local name=$1 want=$2 command=$3 got
  jq -n --arg c "$command" '{tool_input:{command:$c}}' | "$HOOK" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    echo "PASS: $name"
  else
    echo "FAIL: $name (want rc=$want, got rc=$got) -- $command"; fails=$((fails + 1))
  fi
}

echo "-- blocked: kills every agy on the machine"
check "pkill -9 -x agy"            2 'pkill -9 -x agy'
check "pkill -x agy"               2 'pkill -x agy'
check "killall agy"                2 'killall agy'
check "pkill -f agy"               2 'pkill -f agy'
check "pkill -f \"agy --model\""   2 'pkill -f "agy --model"'
check "bracketed generic"          2 'pkill -f "agy [-]-model"'
check "buried in a compound"       2 'echo cleaning; pkill -9 -x agy 2>/dev/null'
check "the exact line my test ran" 2 'kill -9 $BG 2>/dev/null; pkill -9 -x agy 2>/dev/null'
check "unquoted heredoc body"        2 $'cat <<EOF > x.md\npkill -9 -x agy\nEOF'
check "unquoted heredoc backtick"    2 $'cat <<EOF > x.md\n`pkill -9 -x agy`\nEOF'
check "unquoted heredoc \$(...)"      2 $'cat <<EOF > x.md\n$(pkill -9 -x agy)\nEOF'
check "bash heredoc body"            2 $'bash <<\'EOF\'\npkill -9 -x agy\nEOF'
check "python3 heredoc body"         2 $'python3 - <<\'EOF\'\npkill -9 -x agy\nEOF'
check "cat heredoc piped to bash"    2 $'cat <<\'EOF\' | bash\npkill -9 -x agy\nEOF'
check "quoted heredoc to .sh"        2 $'cat <<\'EOF\' > cleanup.sh\npkill -9 -x agy\nEOF'
check "quoted heredoc with no sink"  2 $'cat <<\'EOF\'\npkill -9 -x agy\nEOF'
check "kill on opener line after terminator" 2 $'cat <<\'EOF\' > x.md; pkill -9 -x agy\nsome prose\nEOF'
check "kill on line after terminator" 2 $'cat <<\'EOF\' > x.md\nsome prose\nEOF\npkill -9 -x agy'
check "kill on line before opener"   2 $'pkill -9 -x agy\ncat <<\'EOF\' > x.md\nsome prose\nEOF'
check "kill inside gh pr create body" 2 'gh pr create --body "$(pkill -9 -x agy)"'

echo "-- allowed: scoped to one run, or not agy at all"
check "kill by PID"                0 'kill -9 "$AGY_PID"'
check "kill by captured \$!"        0 'kill -9 $BG 2>/dev/null'
check "run slug pattern"           0 'kill -9 $(pgrep -f "agy-rca-1788190000")'
check "pkill on the slug var"      0 'pkill -f "$SLUG"'
check "unrelated pkill"            0 'pkill -f my-dev-server'
check "pgrep is not a kill"        0 'pgrep -a agy'
check "no kill at all"             0 'git status --porcelain'
check "malformed input"            0 ''
check "hook README row in cat heredoc" 0 $'cat <<\'EOF\' > README.md\n| `hooks/no-broad-agy-kill.sh` | PreToolUse(Bash): blocks a kill targeting agy by name (`pkill -x agy`, `killall agy`). Those reap other sessions\' live runs, which surface there as rc=137 and read as quota death. Kill by PID or by the run\'s `--log-file` slug |\nEOF'
check "double-quoted heredoc delimiter" 0 $'cat <<"EOF" > notes.md\npkill -9 -x agy\nEOF'
check "backslash-escaped delimiter"   0 $'cat <<\\EOF > notes.md\npkill -9 -x agy\nEOF'
check "tee to markdown heredoc"       0 $'tee body.md <<\'EOF\'\npkill -9 -x agy\nEOF'
check "redirect before heredoc operator" 0 $'cat > x.md <<\'EOF\'\npkill -9 -x agy\nEOF'
check "dash heredoc tab-indented terminator" 0 $'cat <<-\'EOF\' > notes.txt\npkill -9 -x agy\n\tEOF'
check "heredoc then gh pr create body-file" 0 $'cat <<\'EOF\' > body.md\npkill -9 -x agy\nEOF\ngh pr create --body-file body.md'

[ "$fails" -eq 0 ] && echo && echo "all no-broad-agy-kill hook tests passed"
exit "$fails"
