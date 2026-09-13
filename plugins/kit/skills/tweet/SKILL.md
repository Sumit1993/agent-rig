---
name: tweet
description: Draft a tweet for @Desolatte about something cool from the current work session. Use when the user says "/tweet", "tweet this", "this is tweetable", or asks to share a finding/idea on X/Twitter.
metadata:
  harnesses: "claude agy"
---

# Tweet drafting for @Desolatte

Live context from the X Context Provider n8n workflow (voice spec, recent posts for dedup, current trending):

!`curl -sf -m 30 -H "X-Context-Token: $(cat ~/.claude/secrets/x-context-token)" "https://n8n.sfun.cloud/webhook/x-context-73826577" | jq '{voice, recentSummary, mentionsProductRecently, trendingSummary, historyFreshAt}'`

If the block above is empty or errored, say so and stop. Do not draft without voice + dedup context. (Check the token file exists and the n8n workflow "X Context Provider" is active.)

## 1. Gather the material

If the user pointed at a specific thing ("tweet about X"), use that. Otherwise review, in order, and pick the most tweet-worthy item:

1. The current conversation, for what this session built or discovered.
2. `git log --oneline -10` in the current repo, for what shipped recently.
3. If a mage KB exists (`mage/metadata.json`): skim `.mage/learnings/` recent entries and any freshly added `mage/notes/` for striking gotchas or insights.

Tweet-worthy = surprising, concrete, useful to other builders. Not tweet-worthy = routine chores, version bumps, private/client details, anything with secrets, tokens, internal URLs, or unreleased plans the user hasn't okayed.

## 2. Draft

Follow the injected `voice` spec EXACTLY. It is the single source of truth, edited only in the n8n workflow, never here. Apply the injected dedup rules:

- Do not repeat any joke, phrasing, or theme visible in `recentSummary`.
- If `mentionsProductRecently` is true, no mage-memory mention in any option.
- `trendingSummary` is optional inspiration. One option MAY riff on a current moment if it fits the session material; never name-drop handles or paste links.

Produce 2-3 options, each ≤280 chars (count it), each a distinct angle (the gotcha, the what-I-built, the human moment). Show them as plain text blocks.

## 3. Hand off

After the user picks (or edits) a draft, open X's compose window pre-filled:

```bash
URL=$(python3 -c "import urllib.parse,sys; print('https://twitter.com/intent/tweet?text='+urllib.parse.quote(sys.argv[1]))" 'TWEET TEXT HERE')
explorer.exe "$URL"
```

(`explorer.exe <url>` opens the default Windows browser from WSL.) The user reviews and hits Post themselves. NEVER post via the X API. Sumit is on a tight X API budget, and the intent URL is free.
