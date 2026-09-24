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
      # The document goes in on stdin, never in the environment: one env entry
      # caps near 128 KiB on Linux, well under the 2 MiB execve total, so a long
      # Bash command reaching in=$(cat) would stop python3 from starting at all.
      # json_get would return 1, the caller would read that as unreadable input
      # and exit 0, and a guard would wave through the one payload big enough to
      # matter. The default is argv[1], which stays small by construction.
      python3 -c '
import json, sys
try:
    doc = json.loads(sys.stdin.read())
except Exception:
    sys.exit(1)
default, paths = sys.argv[1], sys.argv[2:]
for path in paths:
    cur = doc
    for key in path.lstrip(".").split("."):
        cur = cur.get(key) if isinstance(cur, dict) else None
        if cur is None:
            break
    # jq reads `a // b` with null and false alike as unresolved. Match it, or
    # {"session_id": false} yields "false" here and the default under jq.
    if cur is None or cur is False:
        continue
    print(cur if isinstance(cur, str) else json.dumps(cur))
    sys.exit(0)
print(default)
' "$def" "$@" <<<"$doc" 2>/dev/null || return 1
      ;;
    *)
      echo "rig: neither jq nor python3 on PATH; hook payload unreadable." >&2
      return 1
      ;;
  esac
}
