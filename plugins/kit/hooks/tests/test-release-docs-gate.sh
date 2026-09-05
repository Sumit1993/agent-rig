#!/bin/bash
# Regression suite for release-docs-gate.sh (PreToolUse Bash). Fakes kit-meta.sh and
# gh so no real repo state or network is touched. Refs #61.
set -u
HOOK="$(cd "$(dirname "$0")/.." && pwd)/release-docs-gate.sh"
fails=0
FAKEROOT=$(mktemp -d)
FAKEBIN=$(mktemp -d)
CWD=$(mktemp -d)
cleanup() { rm -rf "$FAKEROOT" "$FAKEBIN" "$CWD"; }
trap cleanup EXIT

mkdir -p "$FAKEROOT/scripts"
cat > "$FAKEROOT/scripts/kit-meta.sh" <<'EOF'
#!/bin/bash
case "$1" in
  current) echo "{\"repo\":\"$FAKE_REPO\"}" ;;
  get)
    case "$3" in
      docs) [ "${FAKE_HAS_DOCS:-1}" = "1" ] ;;
      docs_audit_at) echo "${FAKE_DOCS_AUDIT_AT:-0}" ;;
      *) exit 1 ;;
    esac ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$FAKEROOT/scripts/kit-meta.sh"

cat > "$FAKEBIN/gh" <<'EOF'
#!/bin/bash
echo "${FAKE_PR_TITLE:-chore: release 1.0.0}"
EOF
chmod +x "$FAKEBIN/gh"

export CLAUDE_PLUGIN_ROOT="$FAKEROOT" PATH="$FAKEBIN:$PATH" FAKE_REPO=acme/widget

check() { # name want_rc command_str
  local name=$1 want=$2 cmd=$3 got
  printf '{"cwd":"%s","tool_input":{"command":"%s"}}' "$CWD" "$cmd" | "$HOOK" >/dev/null 2>&1
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

FAKE_HAS_DOCS=1 FAKE_DOCS_AUDIT_AT=0 FAKE_PR_TITLE="chore: release 1.0.0"
export FAKE_HAS_DOCS FAKE_DOCS_AUDIT_AT FAKE_PR_TITLE

check "non-merge command passes"       0 "git status"
check "DOCS_GATE=skip marker passes"   0 "gh pr merge 42 --squash DOCS_GATE=skip"
check "stale docs audit blocks"        2 "gh pr merge 42 --squash"

FAKE_HAS_DOCS=0
check "repo without docs block passes" 0 "gh pr merge 42 --squash"
FAKE_HAS_DOCS=1

FAKE_PR_TITLE="fix: something"
check "non-release PR passes"          0 "gh pr merge 42 --squash"

FAKE_PR_TITLE="chore: release 1.0.0"
FAKE_DOCS_AUDIT_AT=$(date +%s)
check "recent docs audit passes"       0 "gh pr merge 42 --squash"

[ "$fails" -eq 0 ] && echo && echo "all release-docs-gate hook tests passed"
exit "$fails"
