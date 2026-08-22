#!/bin/bash
# unslop-drift.sh — prove an unslop rewrite changed prose only.
# Compares before/after for the things a rewrite must never lose: headings,
# code fences, backticked identifiers, links, and list-item count.
#   unslop-drift.sh <before> <after>
set -u
[ "$#" -eq 2 ] || { echo "usage: unslop-drift.sh <before> <after>" >&2; exit 1; }

extract() {
  local f=$1 kind=$2
  case "$kind" in
    headings) grep -E '^#{1,6} ' "$f" | sed 's/[—:].*//' | sed 's/[[:space:]]*$//';;
    fences)   grep -c '^```' "$f";;
    idents)   grep -oE '`[^`]+`' "$f" | sort -u;;
    links)    grep -oE 'https?://[^ )>"]+' "$f" | sort -u;;
    bullets)  grep -cE '^[[:space:]]*[-*] ' "$f";;
    words)    wc -w < "$f";;
  esac
}

fail=0
for kind in headings idents links; do
  if ! diff -q <(extract "$1" "$kind") <(extract "$2" "$kind") >/dev/null; then
    echo "DRIFT in $kind:"
    diff <(extract "$1" "$kind") <(extract "$2" "$kind") | sed 's/^/  /'
    fail=1
  fi
done
for kind in fences bullets; do
  a=$(extract "$1" "$kind"); b=$(extract "$2" "$kind")
  [ "$a" = "$b" ] || { echo "DRIFT in $kind: $a -> $b"; fail=1; }
done
wa=$(extract "$1" words); wb=$(extract "$2" words)
pct=$(( (wb - wa) * 100 / (wa == 0 ? 1 : wa) ))
echo "words: $wa -> $wb (${pct}%)"
[ "${pct#-}" -gt 12 ] && { echo "DRIFT: word count moved more than 12%"; fail=1; }
[ "$fail" -eq 0 ] && echo "no structural drift"
exit $fail
