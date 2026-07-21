---
name: tweet
description: Draft a tweet for @Desolatte about something cool from the current work session. Use when the user says "/tweet", "tweet this", "this is tweetable", or asks to share a finding/idea on X/Twitter.
---

# Tweet drafting for @Desolatte

Goal: turn something from the current session (a finding, a built thing, a gotcha, a "huh, neat" moment) into a tweet the user can post in one click. Draft-only — never post automatically.

## 1. Gather the material

If the user pointed at a specific thing ("tweet about X"), use that. Otherwise review, in order, and pick the most tweet-worthy item:

1. The current conversation — what was built/discovered this session.
2. `git log --oneline -10` in the current repo — what shipped recently.
3. If a mage KB exists (`mage/metadata.json`): skim `.mage/learnings/` recent entries and any freshly added `mage/notes/` for striking gotchas or insights.

Tweet-worthy = surprising, concrete, useful to other builders. Not tweet-worthy = routine chores, version bumps, private/client details, anything with secrets, tokens, internal URLs, or unreleased plans the user hasn't okayed.

## 2. Voice

Follow the voice notes below. If the "Voice examples" section is still empty, ask the user to paste 2-3 of their favorite own tweets, then EDIT THIS FILE to store them under Voice examples so future runs skip the ask.

Voice rules:
- Plain language, no hype words (game-changer, insane, 🚀-speak). Lowercase-casual is fine.
- Concrete detail over abstraction — one real number, error message, or code fragment beats a claim.
- No hashtag spam; at most one if it genuinely helps discovery.
- Builder-to-builder tone: "I hit X, turns out Y" not marketing copy.

### Voice examples

(none yet — ask the user and store them here)

## 3. Draft

Produce 2-3 options, each ≤280 chars (count it). Vary the angle: e.g. the gotcha angle, the "what I built" angle, the one-liner hot-take angle. For threads (only if the material genuinely needs it), number the parts and keep it ≤4 tweets.

Show drafts as plain text blocks so they're easy to copy.

## 4. Hand off

After the user picks a draft (or edits it), open X's compose window pre-filled with it:

```bash
python3 -c "import urllib.parse,sys; print('https://x.com/intent/post?text='+urllib.parse.quote(sys.argv[1]))" 'TWEET TEXT HERE'
explorer.exe "<that url>"
```

(`explorer.exe <url>` opens the default Windows browser from WSL.) The user reviews and hits Post themselves. Never call any X API to post.
