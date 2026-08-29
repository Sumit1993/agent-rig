#!/bin/bash
# unslop-check.sh — flag the mechanically-detectable AI tells from the unslop skill.
# Judgment rules (puffery, soul, active voice) are not checked here; they need a read.
# This catches the ones a regex can prove, plus rule 28 (sentence length), which is a
# word count rather than a pattern and so runs as its own pass.
#   unslop-check.sh [--strict] [paths...]   default paths: repo prose (*.md, docs/*.html)
# --strict exits 1 on any hit, for CI. Default exits 0 and just reports.
set -u

strict=0
[ "${1:-}" = "--strict" ] && { strict=1; shift; }

root=$(git rev-parse --show-toplevel 2>/dev/null) || root=$(cd "$(dirname "$0")/../../.." && pwd)

if [ "$#" -gt 0 ]; then
  files=("$@")
else
  mapfile -t files < <(git -C "$root" ls-files -co --exclude-standard '*.md' 'docs/*.html' | sed "s#^#$root/#")
fi

# rule<TAB>label<TAB>ERE
rules=$(cat <<'RULES'
13	em dash	—
19	curly quote	[“”‘’]
9	not just X but Y	[Nn]ot just .{1,60}, but
7	AI vocabulary	\b([Aa]dditionally|crucial|delve|enduring|enhance[sd]?|fostering|garner|interplay|intricate|pivotal|showcase|testament|underscore[sd]?|vibrant|tapestry)\b
8	fancy "is"	\b(serves as|stands as|boasts|features)\b
23	filler phrase	\b([Ii]n order to|[Dd]ue to the fact that|[Ii]t is important to note that|[Ii]t should be noted that|[Ii]n the event that)\b
31	fancier synonym	\b([Uu]tiliz(e|es|ing|ation)|leverag(e|es|ing)|facilitate[sd]?|numerous|myriad|plethora)\b
24	hedge stack	\b(could potentially|may possibly|might potentially|can potentially)\b
20	chatbot phrase	(I hope this helps|Let me know if|Of course!|Certainly!|Great question)
22	sycophancy	(You're absolutely right|Excellent point|Happy to help)
18	decorative emoji	^#{1,6} .*[🎯🚀✅✨🔥📌💡⚡]
26	metaphor noun	\b([Ss]ubstrates?|wedges? in|[Bb]edrock|scaffolding|modality|paradigm|gold-plating|north star|flywheel)\b
RULES
)

total=0
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  # the unslop skill is a list of the banned words; it always trips its own rules
  case "$f" in */skills/unslop/SKILL.md) continue;; esac
  # blank out fenced code blocks so examples and transcripts are exempt
  # fenced blocks and inline `code` spans are identifiers, not prose: exempt both
  body=$(awk '/^[[:space:]]*```/ {fence = !fence; print ""; next} {print (fence ? "" : $0)}' "$f" \
    | sed 's/`[^`]*`//g; s|<code>[^<]*</code>||g')
  filehits=0
  out=""
  while IFS=$'\t' read -r rule label re; do
    [ -z "${rule:-}" ] && continue
    n=$(printf "%s\n" "$body" | grep -oE "$re" | wc -l || true)
    [ "$n" -eq 0 ] && continue
    filehits=$((filehits + n))
    out="${out}$(printf '  rule %-2s %-18s %3d\n' "$rule" "$label" "$n")"$'\n'
  done <<< "$rules"
  # rule 28: one idea per sentence. Past 35 words, split it. Not a regex, so it runs
  # as its own pass. Table rows and headings are layout, not sentences: skipped.
  n=$(printf "%s\n" "$body" | awk '
    # frontmatter only: the first two delimiters, so a horizontal rule later in
    # the file does not exempt everything after it
    /^---$/ && (NR == 1 || fm) { fm = !fm; next }  fm { next }
    /^[[:space:]]*[|#>]/ { next }
    { gsub(/\[[^]]*\]\([^)]*\)/, "link")
      gsub(/[*_]/, "")   # **bold.** hides the period from the split below
      # ") " is NOT a boundary: a mid-sentence aside would split one long
      # sentence into two short ones and hide it
      k = split($0, s, /[.!?] /)
      for (i = 1; i <= k; i++) if (split(s[i], w, " ") > 35) c++ }
    END { print c + 0 }')
  if [ "$n" -gt 0 ]; then
    filehits=$((filehits + n))
    out="${out}$(printf '  rule %-2s %-18s %3d\n' 28 "long sentence" "$n")"$'\n'
  fi

  if [ "$filehits" -gt 0 ]; then
    printf '%s  (%d)\n%s' "${f#$root/}" "$filehits" "$out"
    total=$((total + filehits))
  fi
done

printf '\ntotal mechanical tells: %d\n' "$total"
[ "$strict" -eq 1 ] && [ "$total" -gt 0 ] && exit 1
exit 0
