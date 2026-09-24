#!/bin/bash
# scripts/check.sh: Run repository documentation checks and tests.
# Matches .github/workflows/lint-docs.yml. Runs every step and reports status. Refs rig#55.
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

failed_steps=()

echo "=== 1. lint-skill-docs"
if bash plugins/rig/scripts/lint-skill-docs.sh; then
  echo "PASS: lint-skill-docs"
else
  echo "FAIL: lint-skill-docs"
  failed_steps+=("lint-skill-docs")
fi
echo

echo "=== 2. hook tests (run-all)"
if bash plugins/rig/hooks/tests/run-all.sh; then
  echo "PASS: hook tests (run-all)"
else
  echo "FAIL: hook tests (run-all)"
  failed_steps+=("hook tests (run-all)")
fi
echo

echo "=== 2.5 query tests (test-queries)"
qt_out=$(bash scripts/queries/tests/test-queries.sh 2>&1)
qt_rc=$?
printf '%s\n' "$qt_out"
if printf '%s\n' "$qt_out" | grep -q '^SKIP: duckdb not installed'; then
  # A missing duckdb exits 0, but that is not a pass: nothing ran (rig#140, 4006888985).
  echo "SKIP: query tests (duckdb not installed)"
elif [ "$qt_rc" -eq 0 ]; then
  echo "PASS: query tests (test-queries)"
else
  echo "FAIL: query tests (test-queries)"
  failed_steps+=("query tests (test-queries)")
fi
echo

echo "=== 2.6 sweep tests"
if bash plugins/rig/scripts/tests/test-ai-context-sweep.sh; then
  echo "PASS: sweep tests"
else
  echo "FAIL: sweep tests"
  failed_steps+=("sweep tests")
fi
echo

echo "=== 4. rule load (report-only)"
# Lines, and story lines (a date, a PR number, "tonight", "we learned") per always-loaded file
# and per skill. Information, not a gate: length has no measured effect on compliance, rule
# count does. Refs #123
for f in dotfiles/AGENTS.md plugins/rig/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  lines=$(wc -l < "$f" | tr -d ' ')
  story=$(grep -cE '20[0-9]{2}-[0-9]{2}|#[0-9]{2,4}\b|tonight|we learned|last week' "$f" || true)
  printf '%5s lines %3s story  %s\n' "$lines" "$story" "$f"
done
echo "PASS: rule load reported"
echo

echo "=== 5. record hygiene (report-only)"
# Rule count in dotfiles/AGENTS.md
if [ -f "dotfiles/AGENTS.md" ]; then
  rule_count=$(grep -vE '^[[:space:]]*$|^#|^@' dotfiles/AGENTS.md | wc -l | tr -d ' ')
  echo "INFO: AGENTS.md rules: $rule_count"
else
  echo "SKIP: dotfiles/AGENTS.md missing"
fi

# Skill description length
desc_lengths=()
warned_desc=0
for sk in plugins/rig/skills/*/SKILL.md; do
  [ -f "$sk" ] || continue
  dval=$(sed -n -E 's/^description:[[:space:]]*//p' "$sk" | head -1)
  dval=$(echo "$dval" | sed -E 's/^["'"'"']//; s/["'"'"']$//')
  len=${#dval}
  if [ "$len" -gt 300 ]; then
    sk_name=$(basename "$(dirname "$sk")")
    echo "WARN: $sk_name description over 300 chars ($len)"
    warned_desc=1
  fi
  desc_lengths+=("$len")
done
if [ "$warned_desc" -eq 0 ] && [ "${#desc_lengths[@]}" -gt 0 ]; then
  sorted=($(printf '%s\n' "${desc_lengths[@]}" | sort -n))
  mid=$(( ${#sorted[@]} / 2 ))
  median="${sorted[$mid]}"
  echo "INFO: skill description length: median $median chars"
fi

# .worktreeinclude
if [ -f ".worktreeinclude" ]; then
  echo "INFO: .worktreeinclude present"
else
  echo "WARN: no .worktreeinclude; lanes that build get no gitignored files"
fi

# Milestone against the release PR
if ! command -v gh >/dev/null 2>&1; then
  echo "SKIP: milestone check (gh unavailable)"
else
  # gh --search drops the parenthesised title; filter client-side instead.
  rel_json=$(gh pr list --state open --limit 1000 --json title 2>/dev/null)
  rel_rc=$?
  if [ $rel_rc -ne 0 ]; then
    echo "SKIP: milestone check (gh unavailable)"
  else
    rel_title=$(jq -r '[.[] | select(.title | startswith("chore(master): release"))][0].title // empty' <<<"$rel_json" 2>/dev/null)
    if [ -z "$rel_title" ]; then
      echo "INFO: milestone check (no open release PR)"
    else
      ver=$(grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' <<<"$rel_title" | head -1)
      [ -n "$ver" ] || ver="$rel_title"
      ms_json=$(gh api --paginate "repos/:owner/:repo/milestones?state=all&per_page=100" 2>/dev/null)
      ms_rc=$?
      [ $ms_rc -eq 0 ] && ms_json=$(jq -s 'add // []' <<<"$ms_json")
      if [ $ms_rc -ne 0 ]; then
        echo "SKIP: milestone check (gh unavailable)"
      else
        ms=$(jq -c --arg v "$ver" '.[] | select(.title == $v)' <<<"$ms_json" 2>/dev/null | head -1)
        if [ -z "$ms" ]; then
          echo "WARN: milestone $ver does not exist"
        else
          ms_state=$(jq -r '.state // ""' <<<"$ms")
          ms_open_issues=$(jq -r '.open_issues // 0' <<<"$ms")
          if [ "$ms_state" = "open" ] && [ "$ms_open_issues" -gt 0 ]; then
            echo "WARN: milestone $ver is open with $ms_open_issues open issues"
          elif [ "$ms_state" = "open" ]; then
            echo "WARN: milestone $ver is open"
          else
            echo "INFO: milestone $ver closed"
          fi
        fi
      fi
    fi
  fi
fi

# Labels per registry repo
if [ -f "plugins/rig/data/repo-meta.json" ] && command -v gh >/dev/null 2>&1; then
  req_labels="bug enhancement documentation decision blocked parked needs-operator p0 p1"
  for rk in $(jq -r 'keys[]' plugins/rig/data/repo-meta.json 2>/dev/null); do
    lbl_json=$(gh label list -R "$rk" --limit 1000 --json name 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$lbl_json" ]; then
      echo "SKIP: labels check $rk (gh unavailable)"
    else
      missing_lbls=()
      existing_lbls=$(jq -r '.[].name' <<<"$lbl_json" 2>/dev/null)
      for req in $req_labels; do
        grep -qwF "$req" <<<"$existing_lbls" || missing_lbls+=("$req")
      done
      if [ ${#missing_lbls[@]} -gt 0 ]; then
        echo "WARN: $rk missing: ${missing_lbls[*]}"
      else
        echo "INFO: $rk labels complete"
      fi
    fi
  done
else
  echo "SKIP: repo-meta labels check"
fi

# Sweep
ai_root="${AI_CONTEXT_ROOT:-$HOME/ai-context}"
if [ -d "$ai_root" ] && [ -f "plugins/rig/scripts/ai-context-sweep.sh" ]; then
  sweep_summary=$(bash plugins/rig/scripts/ai-context-sweep.sh 2>/dev/null | tail -1)
  echo "INFO: $sweep_summary"
else
  echo "SKIP: no ai-context"
fi
echo "PASS: record hygiene reported"
echo

if [ "${#failed_steps[@]}" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Checks failed: ${failed_steps[*]}."
  exit 1
fi
