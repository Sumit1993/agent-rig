#!/bin/bash
# rig-meta.sh — per-repo metadata for rig tooling.
#   get <owner/repo> <key>               print the value (exit 1 if unset)
#   current [<key>]                      repo resolved from the cwd's origin remote
#   observe <owner/repo> <key> <value>   record a runtime observation
# Truth folds two layers on read: data/repo-meta.json (versioned, curated — wins
# on conflict) over ~/ai-context/state/rig/observed.json (runtime, never committed).
set -u
DATA="$(cd "$(dirname "$0")/.." && pwd)/data/repo-meta.json"
STATE_DIR="$HOME/ai-context/state/rig"
OBSERVED="$STATE_DIR/observed.json"

merged() { jq -s '.[0] * .[1]' <(cat "$OBSERVED" 2>/dev/null || echo '{}') "$DATA"; }

resolve_repo() {
  local url
  url=$(git remote get-url origin 2>/dev/null) || return 1
  case "$url" in
    *github.com*) printf '%s\n' "$url" | sed -E 's#.*github\.com[:/]##; s#\.git$##';;
    *) return 1;;
  esac
}

case "${1:-}" in
  get)
    # `// empty` swallows a literal false, so a false-valued key read as unset.
    # has() separates "set to false" from "absent"; `enforced` depends on the difference.
    v=$(merged | jq -r --arg r "${2:?owner/repo}" --arg k "${3:?key}" \
          '(.[$r] // {}) | if has($k) and .[$k] != null then .[$k] else empty end')
    [ -n "$v" ] || exit 1
    echo "$v";;
  current)
    repo=$(resolve_repo) || { echo "rig-meta: no github origin in cwd" >&2; exit 1; }
    if [ -n "${2:-}" ]; then exec "$0" get "$repo" "$2"; fi
    merged | jq -c --arg r "$repo" '{repo: $r} + (.[$r] // {})';;
  observe)
    repo="${2:?owner/repo}"; key="${3:?key}"; val="${4:?value}"
    # Plain `jq .`, never `jq -e .`: -e exits 1 on false and null, so an observed
    # `false` got stored as the string "false" while curated data holds a boolean.
    jq . >/dev/null 2>&1 <<<"$val" || val=$(jq -Rn --arg v "$val" '$v')
    mkdir -p "$STATE_DIR"
    tmp=$(mktemp "$STATE_DIR/.observed.XXXXXX")
    (cat "$OBSERVED" 2>/dev/null || echo '{}') \
      | jq --arg r "$repo" --arg k "$key" --argjson v "$val" '.[$r] = ((.[$r] // {}) + {($k): $v})' > "$tmp" \
      && mv "$tmp" "$OBSERVED";;
  *)
    echo "usage: rig-meta.sh get <owner/repo> <key> | current [<key>] | observe <owner/repo> <key> <value>" >&2
    exit 2;;
esac
