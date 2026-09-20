# mage:rig/lib/json
# One JSON read for a hook payload, so a guard keeps working when jq is absent.
# jq first, python3 second. The 2026-09-16 rebuild left this machine with no jq
# at all, and every jq-reading hook here answers an unreadable payload with
# exit 0, so each guard silently passed everything until a jq turned up.
#
# Malformed input still never blocks: that is doctrine, and the tests assert it.
# This only stops a MISSING PARSER from looking like malformed input.

json_runtime() {
  if command -v jq >/dev/null 2>&1; then echo jq
  elif command -v python3 >/dev/null 2>&1; then echo python3
  else echo none
  fi
}

# json_get <doc> <default> <dotted-path> [<dotted-path>...]
# First path resolving to a non-null value wins, <default> when none do.
# Returns 1 when the document does not parse or no runtime can read it.
json_get() {
  local doc="$1" def="$2"; shift 2
  case "$(json_runtime)" in
    jq)
      local filter="" p
      for p in "$@"; do filter="${filter}${filter:+ // }.${p#.}"; done
      jq -r "${filter} // \$d" --arg d "$def" <<<"$doc" 2>/dev/null || return 1
      ;;
    python3)
      RIG_DOC="$doc" RIG_DEF="$def" python3 -c '
import json, os, sys
try:
    doc = json.loads(os.environ["RIG_DOC"])
except Exception:
    sys.exit(1)
for path in sys.argv[1:]:
    cur = doc
    for key in path.lstrip(".").split("."):
        cur = cur.get(key) if isinstance(cur, dict) else None
        if cur is None:
            break
    if cur is not None:
        print(cur if isinstance(cur, str) else json.dumps(cur))
        sys.exit(0)
print(os.environ["RIG_DEF"])
' "$@" 2>/dev/null || return 1
      ;;
    *)
      echo "rig: neither jq nor python3 on PATH; hook payload unreadable." >&2
      return 1
      ;;
  esac
}
