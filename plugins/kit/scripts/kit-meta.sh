#!/bin/bash
# kit-meta.sh — per-repo metadata for claude-kit tooling.
#   get <owner/repo> <key>               print the value (exit 1 if unset)
#   current [<key>]                      repo resolved from the cwd's origin remote
#   observe <owner/repo> <key> <value>   record a runtime observation
# Truth folds two layers on read: data/repo-meta.json (versioned, curated — wins
# on conflict) over ~/ai-context/state/kit/observed.json (runtime, never committed).
set -u
DATA="$(cd "$(dirname "$0")/.." && pwd)/data/repo-meta.json"
STATE_DIR="$HOME/ai-context/state/kit"
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
    v=$(merged | jq -r --arg r "${2:?owner/repo}" --arg k "${3:?key}" '.[$r][$k] // empty')
    [ -n "$v" ] || exit 1
    echo "$v";;
  current)
    repo=$(resolve_repo) || { echo "kit-meta: no github origin in cwd" >&2; exit 1; }
    if [ -n "${2:-}" ]; then exec "$0" get "$repo" "$2"; fi
    merged | jq -c --arg r "$repo" '{repo: $r} + (.[$r] // {})';;
  observe)
    repo="${2:?owner/repo}"; key="${3:?key}"; val="${4:?value}"
    jq -e . >/dev/null 2>&1 <<<"$val" || val=$(jq -Rn --arg v "$val" '$v')
    mkdir -p "$STATE_DIR"
    tmp=$(mktemp "$STATE_DIR/.observed.XXXXXX")
    (cat "$OBSERVED" 2>/dev/null || echo '{}') \
      | jq --arg r "$repo" --arg k "$key" --argjson v "$val" '.[$r] = ((.[$r] // {}) + {($k): $v})' > "$tmp" \
      && mv "$tmp" "$OBSERVED";;
  *)
    echo "usage: kit-meta.sh get <owner/repo> <key> | current [<key>] | observe <owner/repo> <key> <value>" >&2
    exit 2;;
esac
