#!/bin/bash
# watch-coderabbit.sh [--repo owner/name] <pr#> [<pr#>...]
# Deterministic PR watcher for Claude Code's Monitor tool. Emits ONE stdout line per:
#   - new CodeRabbit review comment (thread root or reply)
#   - CodeRabbit rate-limit block (NO review ran) + the auto re-trigger once the window elapses
#   - CI check that newly turned red
#   - PR reaching MERGED/CLOSED (then dropped from the watch)
# Exits when no watched PRs remain. Seen-state persists in ~/ai-context/state/cr-watch
# keyed by owner-repo-prN, so re-arming never re-emits old comments.
# Repo defaults to the current directory's origin remote.
#
# Rate limits: when CodeRabbit is out of quota it
# posts the notice as an ISSUE comment, not a review comment — a watcher polling only
# /pulls/N/comments sees nothing and waits forever. It also posts a check named
# "Review rate limited" that PASSES by design (so it never blocks merge on protected
# branches), so the red-check loop can't see it either. Both channels are silent; this
# script polls /issues/N/comments for the marker and treats it as a first-class event.
# Not every repo has CodeRabbit (the hubs do not). A repo without the app emits no review
# comments AND no rate-limit notice — byte-identical to "reviewed, found nothing". So the
# watcher probes once at startup and SAYS so; a silent watch must never read as a clean
# review that never happened.
# Env: CR_WATCH_AUTORETRY=0 disables posting `@coderabbitai review` (detect-only).
#      CR_WATCH_MAX_RETRIES=N caps auto re-triggers per PR (default 2).
#      CR_WATCH_ASSUME_CODERABBIT=1|0 skips the probe (force present/absent).
#      CR_WATCH_COOLDOWN_SECONDS=N auto-retry delay used ONLY when the notice's own
#      figure cannot be parsed (default 3600).
set -u
if [ "${1:-}" = "--repo" ]; then REPO="$2"; shift 2; else
  REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || { echo "watch-coderabbit: cannot resolve repo (pass --repo owner/name)"; exit 1; }
fi
KEY=$(echo "$REPO" | tr '/' '-')
STATE_DIR="${CR_WATCH_STATE_DIR:-$HOME/ai-context/state/cr-watch}"
mkdir -p "$STATE_DIR"
PRS=("$@")
[ ${#PRS[@]} -eq 0 ] && { echo "watch-coderabbit: no PR numbers given"; exit 1; }
AUTORETRY=${CR_WATCH_AUTORETRY:-1}
MAX_RETRIES=${CR_WATCH_MAX_RETRIES:-2}
declare -A FAILED_SEEN
gh_fail=0

# True (exit 0) iff stdin is valid JSON whose top-level type is "array".
# gh api returns a JSON *object* (e.g. {"message":"Server Error"}) instead of
# the expected array on transient failures (5xx, rate limiting). `.[]` still
# "iterates" an object — over its values — so an unguarded filter treats that
# garbage as real API records: phantom events, and worse, ids written into
# the seen-state file that persist across sessions. Every gh api response
# that gets iterated or counted as a list must clear this gate first; skip
# the cycle (no event, no state write) when it doesn't.
is_json_array() {
  jq -e 'type == "array"' >/dev/null 2>&1
}

# --- CodeRabbit presence probe (once, at startup) ---
# Fast path: the kit-meta registry (data/repo-meta.json + observed.json). Otherwise
# cheap and conservative: a committed config, or the bot having spoken anywhere in the
# repo's recent comment history. Either is proof the app is wired; neither means it is not.
# A positive probe upserts the registry so every later consumer skips the API calls.
KIT_META="$(cd "$(dirname "$0")/../../scripts" 2>/dev/null && pwd)/kit-meta.sh"
found() {
  [ -x "$KIT_META" ] && "$KIT_META" observe "$REPO" coderabbit true >/dev/null 2>&1
  echo 1
}
detect_coderabbit() {
  if [ -x "$KIT_META" ] && [ "$("$KIT_META" get "$REPO" coderabbit 2>/dev/null)" = "true" ]; then echo 1; return; fi
  gh api "repos/$REPO/contents/.coderabbit.yaml" >/dev/null 2>&1 && { found; return; }
  gh api "repos/$REPO/contents/.coderabbit.yml"  >/dev/null 2>&1 && { found; return; }
  local n raw
  for endpoint in "issues/comments" "pulls/comments"; do
    raw=$(gh api "repos/$REPO/$endpoint?per_page=100" 2>/dev/null)
    is_json_array <<<"$raw" || continue
    n=$(jq '[.[] | select(.user.login | test("coderabbit";"i"))] | length' <<<"$raw" 2>/dev/null)
    case "$n" in ''|*[!0-9]*) n=0;; esac
    [ "$n" -gt 0 ] && { found; return; }
  done
  echo 0
}
CR_PRESENT=${CR_WATCH_ASSUME_CODERABBIT:-$(detect_coderabbit)}
if [ "$CR_PRESENT" = "1" ]; then
  echo "CODERABBIT ACTIVE on $REPO — watching reviews, rate limits, CI and merge state"
else
  echo "CODERABBIT ABSENT on $REPO — watching CI + merge state ONLY. No review will arrive, so silence here is NOT a clean review: get line-level coverage from a model review pass."
fi

# Seconds until the next review window, parsed from the rate-limit notice.
# CodeRabbit has used at least three wordings, so match on "review …available in <n> <unit>"
# rather than any one phrasing:
#   "Next review available in: **47 minutes**"                  (older, colon)
#   "**Next included review available in 30 minutes.**"         (no colon, "included")
#   "Your next included review will be available in 23 minutes."
# The notice's figure is obeyed, not floored: it is the per-developer window anchored to the
# last accepted review and measures exact to within fifteen seconds. A flat 3600s counts
# from the REFUSAL instead, landing ~21 minutes late. The fallback covers only a notice
# with no figure in it. RETRY_NOTICE records the claim so the event line names its source.
# Measurements: claude-kit#28.
COOLDOWN_SECONDS=${CR_WATCH_COOLDOWN_SECONDS:-3600}
# Validate before it ever reaches arithmetic. A junk value flows through the fallback path
# into $((secs / 60)), where bash treats a non-numeric literal as a variable name and
# `set -u` kills the whole poller — every PR in this invocation, not just this one.
case "$COOLDOWN_SECONDS" in ''|*[!0-9]*) COOLDOWN_SECONDS=3600 ;; esac
# Sets RETRY_SECS and RETRY_NOTICE. Call it plainly, never as $(retry_seconds ...):
# command substitution runs it in a subshell and both globals are lost on return.
RETRY_SECS=$COOLDOWN_SECONDS
RETRY_NOTICE=""
retry_seconds() {
  local parsed num unit
  RETRY_NOTICE=""; RETRY_SECS=$COOLDOWN_SECONDS
  parsed=$(printf '%s\n' "$1" \
    | sed -n 's/.*review[^0-9]*available in[^0-9]*\([0-9][0-9]*\)[^a-zA-Z]*\([a-zA-Z]*\).*/\1 \2/p' \
    | head -1)
  num=${parsed%% *}; unit=${parsed#* }
  case "$num" in ''|*[!0-9]*) return;; esac
  case "$unit" in hour*|Hour*) RETRY_NOTICE=$((num * 3600));; *) RETRY_NOTICE=$((num * 60));; esac
  RETRY_SECS=$RETRY_NOTICE
}

# PRs whose rate-limit state this process has already evaluated once (see the recovery
# block below). Per process, not per poll.
rl_seen=""

while [ ${#PRS[@]} -gt 0 ]; do
  next=()
  for pr in "${PRS[@]}"; do
    state=$(gh pr view "$pr" --repo "$REPO" --json state --jq .state 2>/dev/null) || { gh_fail=$((gh_fail+1)); next+=("$pr"); continue; }
    gh_fail=0
    if [ "$state" != "OPEN" ]; then
      echo "PR#$pr $state — dropped from watch"
      continue
    fi
    next+=("$pr")

    if [ "$CR_PRESENT" = "1" ]; then
    seen="$STATE_DIR/$KEY-pr$pr.seen"; touch "$seen"
    # Pointer, not payload: the full comment body goes to a state file; the event
    # line carries its path plus a short excerpt. The session that owns the Monitor
    # routes the path to a seat — comment bodies never enter the main context.
    payload_dir="$STATE_DIR/$KEY-pr$pr-comments"; mkdir -p "$payload_dir"
    comments_raw=$(gh api "repos/$REPO/pulls/$pr/comments?per_page=100" 2>/dev/null)
    if is_json_array <<<"$comments_raw"; then
      jq -r '.[] | select(.user.login | test("coderabbit")) | "\(.id)\t\(.path):\(.line // .original_line)\t\(.in_reply_to_id // "root")\t\(.body | gsub("[\\n\\r\\t]"; " ") | .[0:80])"' <<<"$comments_raw" |
      while IFS=$'\t' read -r id path reply body; do
        grep -qx "$id" "$seen" 2>/dev/null && continue
        echo "$id" >> "$seen"
        kind="thread"; [ "$reply" != "root" ] && kind="reply-in-$reply"
        gh api "repos/$REPO/pulls/comments/$id" > "$payload_dir/$id.json" 2>/dev/null
        echo "PR#$pr NEW coderabbit $kind — id $id — $path — payload $payload_dir/$id.json — $body"
      done
    fi

    # --- chat-misread channel (issue comments) ---
    # A `@coderabbitai review` comment carrying prose and questions can be answered as a
    # CHAT instead of running a review. From outside it is indistinguishable from a slow
    # review: no rate-limit notice, no findings, nothing red — just silence. Observed on
    # prismalens#400, where it cost ~50 minutes before anyone looked at the reply body.
    #
    # The tell is CodeRabbit's own hint, which it appends to chat answers and not to
    # reviews. Reported once per occurrence (dedupe on updated_at, same reason as below).
    chat_state="$STATE_DIR/$KEY-pr$pr.chatmisread"
    chat_prev=""; [ -f "$chat_state" ] && chat_prev=$(cat "$chat_state" 2>/dev/null)
    ar_state="$STATE_DIR/$KEY-pr$pr.alreadyreviewed"
    ar_prev=""; [ -f "$ar_state" ] && ar_prev=$(cat "$ar_state" 2>/dev/null)
    ic_raw=$(gh api "repos/$REPO/issues/$pr/comments?per_page=100" 2>/dev/null)
    if is_json_array <<<"$ic_raw"; then
      chat_ts=$(jq -r '[.[] | select(.user.login | test("coderabbit"))
                      | select(.body | test("initiate chat on the files"))]
                 | last | .updated_at // empty' <<<"$ic_raw" 2>/dev/null)
      if [ -n "$chat_ts" ] && [ "$chat_ts" != "$chat_prev" ]; then
        printf '%s' "$chat_ts" > "$chat_state"
        # This fires on any chat-formatted reply, including a perfectly correct answer to a
        # comment that was never a trigger. Say what happened and let the reader decide,
        # rather than prescribing a re-trigger that may be a no-op or a wasted slot.
        echo "PR#$pr CODERABBIT ANSWERED AS CHAT — the latest reply is a chat answer, not a review. If the comment it answered was meant as a review trigger, re-post it BARE with nothing else and put context in the PR body."
      fi

      # A DIFFERENT refusal with the opposite meaning, and the one this watcher used to
      # miss entirely: CodeRabbit declining because the head is already reviewed. Nothing
      # matched it, so a refused trigger looked like a review still in flight, and the
      # nearest event said "no review ran" when the head IS reviewed. `coderabbit-lane` §4
      # already separates the two refusals; the watcher now does too. Story: claude-kit#28.
      ar_ts=$(jq -r '[.[] | select(.user.login | test("coderabbit"))
                      | select(.body | test("already reviewed commits|Already reviewed the last commit"))]
                 | last | .updated_at // empty' <<<"$ic_raw" 2>/dev/null)
      if [ -n "$ar_ts" ] && [ "$ar_ts" != "$ar_prev" ]; then
        printf '%s' "$ar_ts" > "$ar_state"
        echo "PR#$pr CODERABBIT ALREADY REVIEWED — the trigger was refused because this head is already reviewed. No new review ran and none is coming. Only '@coderabbitai full review' reruns it, and it draws the same budget."
      fi
    fi

    # --- rate-limit channel (issue comments) ---
    # CodeRabbit keeps ONE summary issue comment per PR and EDITS it, so the comment id is
    # stable across pushes — dedupe on updated_at, not id, or a second block never fires.
    rl_state="$STATE_DIR/$KEY-pr$pr.ratelimit"
    prev_ts=""; retry_at=0; used=0
    [ -f "$rl_state" ] && IFS=$'\t' read -r prev_ts retry_at used < "$rl_state"
    case "$retry_at" in ''|*[!0-9]*) retry_at=0;; esac
    case "$used" in ''|*[!0-9]*) used=0;; esac

    rl_raw=$(gh api "repos/$REPO/issues/$pr/comments?per_page=100" 2>/dev/null)
    if is_json_array <<<"$rl_raw" && rl=$(jq -r '[.[] | select(.user.login | test("coderabbit"))
                         | select(.body | test("rate limited by coderabbit\\.ai"))]
                    | if length > 0 then last | "\(.updated_at)\t\(.body | gsub("[\\n\\r\\t]"; " "))"
                      else empty end' <<<"$rl_raw" 2>/dev/null); then
      # `last` on an empty array yields the string "null\tnull", not null or empty, so the
      # length check must come before any interpolation, otherwise the guard is unreachable
      # and the branch reports the opposite of what happened.
      if [ "$rl" = "null" ] || [ -z "$rl" ]; then
        # Notice gone => a real review ran and replaced it. Existing thread poll covers the findings.
        if [ -f "$rl_state" ]; then
          rm -f "$rl_state"
          echo "PR#$pr CODERABBIT RESUMED — rate-limit notice cleared, review ran"
        fi
      else
        rl_ts=${rl%%$'\t'*}; rl_body=${rl#*$'\t'}
        # Edge-triggering on updated_at alone silently drops the retry when a watcher is
        # re-armed after the notice was already recorded: the new process reads the same
        # timestamp, skips the arming path, and leaves retry_at at 0 forever. Silence then
        # looks exactly like an armed wait. So a process also arms on its FIRST sight of a
        # PR that has a recorded notice and nothing armed. Once per process, never per
        # poll, or a spent retry would immediately re-arm itself off the stale notice.
        # Story: claude-kit#28, 29 minutes lost on gh-workflows#98.
        rl_first=0
        case " $rl_seen " in *" $pr "*) ;; *) rl_first=1; rl_seen="$rl_seen $pr";; esac
        # used=0 is the whole test for "arming was lost": a spent retry means a trigger
        # was already posted for THIS notice, so nothing was lost and re-firing would
        # spend another one. A refusal of that trigger arrives as a new notice anyway.
        recover=0
        [ "$rl_first" = "1" ] && [ "$rl_ts" = "$prev_ts" ] && [ "$retry_at" = "0" ] \
          && [ "$used" = "0" ] && [ "$AUTORETRY" = "1" ] && recover=1
        if [ "$rl_ts" != "$prev_ts" ] || [ "$recover" = "1" ]; then
          retry_seconds "$rl_body"; secs=$RETRY_SECS
          if [ "$AUTORETRY" != "1" ]; then
            armed="window $((secs / 60))m; auto-retry OFF (CR_WATCH_AUTORETRY=0) — re-trigger by hand or run the model review pass"
            retry_at=0
          elif [ "$used" -lt "$MAX_RETRIES" ]; then
            claimed="notice unparsed, using the ${COOLDOWN_SECONDS}s fallback"
            [ -n "$RETRY_NOTICE" ] && claimed="the notice's own figure"
            armed="auto-retry armed ($claimed) (attempt $((used + 1))/$MAX_RETRIES)"
            # Anchored to the notice, not to now. The notice's figure counts from when it
            # was posted, so a watcher armed late must not restart the clock.
            notice_epoch=$(date -u -d "$rl_ts" +%s 2>/dev/null) || notice_epoch=""
            case "$notice_epoch" in ''|*[!0-9]*) notice_epoch=$(date +%s);; esac
            retry_at=$(( notice_epoch + secs + 60 ))   # +60s slack: never re-trigger a beat early
          else
            armed="auto-retry budget spent ($MAX_RETRIES) — run the model review pass instead of waiting"
            retry_at=0
          fi
          if [ "$recover" = "1" ]; then
            echo "PR#$pr CODERABBIT RETRY RECOVERED — a recorded notice had no retry armed; $armed"
          else
            echo "PR#$pr CODERABBIT RATE-LIMITED — no review ran; $armed"
          fi
          # The only positive signal used to be RE-TRIGGERED, which by definition never
          # arrives when the arming was lost. Say when the retry will fire, in UTC.
          if [ "$retry_at" -gt 0 ]; then
            at=$(date -u -d "@$retry_at" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")
            echo "PR#$pr CODERABBIT RETRY ARMED — will re-trigger at $at"
          fi
          printf '%s\t%s\t%s\n' "$rl_ts" "$retry_at" "$used" > "$rl_state"
          prev_ts="$rl_ts"
        fi
        # Window elapsed: a blocked push consumes no quota, so re-triggering is free.
        if [ "$retry_at" -gt 0 ] && [ "$(date +%s)" -ge "$retry_at" ]; then
          if gh api "repos/$REPO/issues/$pr/comments" -f body="@coderabbitai review" >/dev/null 2>&1; then
            echo "PR#$pr CODERABBIT RE-TRIGGERED — posted @coderabbitai review (attempt $((used + 1))/$MAX_RETRIES)"
          else
            echo "PR#$pr CODERABBIT RE-TRIGGER FAILED — post '@coderabbitai review' by hand"
          fi
          printf '%s\t0\t%s\n' "$prev_ts" "$((used + 1))" > "$rl_state"
        fi
      fi
    fi

    # --- auto-pause channel (issue comments; dedupe on updated_at, same as above) ---
    ap_state="$STATE_DIR/$KEY-pr$pr.autopause"
    ap_prev=""; [ -f "$ap_state" ] && ap_prev=$(cat "$ap_state" 2>/dev/null)
    if is_json_array <<<"$rl_raw" && ap_ts=$(jq -r '[.[] | select(.user.login | test("coderabbit"))
                         | select(.body | test("review paused by coderabbit\\.ai"))]
                    | last | .updated_at // empty' <<<"$rl_raw" 2>/dev/null); then
      if [ -z "$ap_ts" ] || [ "$ap_ts" = "null" ]; then
        if [ -f "$ap_state" ]; then
          rm -f "$ap_state"
          echo "PR#$pr CODERABBIT AUTO-PAUSE CLEARED — reviews resumed"
        fi
      elif [ "$ap_ts" != "$ap_prev" ]; then
        printf '%s' "$ap_ts" > "$ap_state"
        echo "PR#$pr CODERABBIT AUTO-PAUSED — no review ran; resume with '@coderabbitai resume'"
      fi
    fi
    fi  # CR_PRESENT

    # --- Claude review lane channel (inline comments + liveness verdict) ---
    seen_claude="$STATE_DIR/$KEY-pr$pr-claude.seen"; touch "$seen_claude"
    payload_dir="$STATE_DIR/$KEY-pr$pr-comments"; mkdir -p "$payload_dir"
    claude_comments_raw=$(gh api "repos/$REPO/pulls/$pr/comments?per_page=100" 2>/dev/null)
    if is_json_array <<<"$claude_comments_raw"; then
      jq -r '.[] | select(.user.login == "claude[bot]" or (.user.login | test("claude"; "i"))) | "\(.id)\t\(.path):\(.line // .original_line)\t\(.in_reply_to_id // "root")\t\(.body | gsub("[\\n\\r\\t]"; " ") | .[0:80])"' <<<"$claude_comments_raw" |
      while IFS=$'\t' read -r id path reply body; do
        grep -qx "$id" "$seen_claude" 2>/dev/null && continue
        echo "$id" >> "$seen_claude"
        kind="thread"; [ "$reply" != "root" ] && kind="reply-in-$reply"
        gh api "repos/$REPO/pulls/comments/$id" > "$payload_dir/$id.json" 2>/dev/null
        echo "PR#$pr NEW claude $kind — id $id — $path — payload $payload_dir/$id.json — $body"
      done
    fi

    liveness_state="$STATE_DIR/$KEY-pr$pr.claudeliveness"
    liveness_prev=""
    [ -f "$liveness_state" ] && liveness_prev=$(cat "$liveness_state" 2>/dev/null)
    liveness_raw=$(gh api "repos/$REPO/issues/$pr/comments?per_page=100" 2>/dev/null)
    if is_json_array <<<"$liveness_raw"; then
      # Match the marker PREFIX, never the whole marker: it carries a round counter
      # (`<!-- claude-review-liveness rounds=N -->`) that changes on every automatic
      # round, so an exact-string match silently stops seeing the comment.
      liveness_info=$(jq -r '[.[] | select((.user.login == "github-actions[bot]" or (.user.login | test("github-actions"; "i"))) and (.body | startswith("<!-- claude-review-liveness")))]
                             | if length > 0 then last | "\(.updated_at)\t\(.body | sub("^<!-- claude-review-liveness[^>]*-->\\s*"; "") | split("\n") | map(select(length > 0)) | first)" else empty end' <<<"$liveness_raw" 2>/dev/null)
      if [ -n "$liveness_info" ]; then
        liveness_ts=${liveness_info%%$'\t'*}
        liveness_text=${liveness_info#*$'\t'}
        if [ "$liveness_ts" != "$liveness_prev" ]; then
          printf '%s' "$liveness_ts" > "$liveness_state"
          echo "PR#$pr CLAUDE LIVENESS — $liveness_text"
        fi
      fi
    fi

    # Read line-by-line: check names contain spaces ("Validate PR title (conventional
    # commits)"), and `for r in $reds` word-splits them into one bogus event per word.
    # A here-string keeps FAILED_SEEN in this shell — a pipe would subshell it and
    # every red would re-fire every cycle.
    reds=$(gh pr checks "$pr" --repo "$REPO" 2>/dev/null | awk -F'\t' '$2=="fail" {print $1}')
    while IFS= read -r r; do
      [ -z "$r" ] && continue
      key="$pr:$r"
      [ "${FAILED_SEEN[$key]:-}" = "1" ] && continue
      FAILED_SEEN[$key]=1
      echo "PR#$pr CI FAIL — $r"
    done <<< "$reds"
  done
  # NB: not PRS=("${next[@]:-}") — empty array expands to one "" element and the exit check never fires
  [ ${#next[@]} -eq 0 ] && break
  PRS=("${next[@]}")
  [ "$gh_fail" -ge 5 ] && { echo "WATCHER DEGRADED — gh failing repeatedly (auth/network?)"; gh_fail=0; }
  sleep 75
done
echo "watch-coderabbit: all watched PRs closed — exiting"
