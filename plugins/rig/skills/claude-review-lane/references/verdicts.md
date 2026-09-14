# Liveness verdicts

Every `verdict_kind` the lane can post, whether it means the head was reviewed, and what to do. Read this when a liveness comment is in front of you and its text is not one of the two `reviewed <sha> ...` forms.

Nineteen `verdict_kind` values, read from `claude-code-review.yml` at gh-workflows 1b1c597. Only the first two rows mean the head was reviewed:

| Verdict text | Reviewed? | What to do |
|---|---|---|
| `reviewed <sha> and posted N inline / M summary comment(s)` | Yes | Work the threads |
| `reviewed <sha> (incremental from <base>) and posted N inline / M summary comment(s)` | Yes | Work the threads |
| `finished on <sha> (job result: ...) but posted **nothing**` | No | Read the run log for tool denials, then `@claude full review`. If that also comes back empty, escalate to `coderabbit_review` or a model pass |
| `re-checked open threads at <sha>: N resolved / M left open` | No, threads only | Not review evidence for this head; `8/8 resolved` is not clean |
| `re-checked open threads at <sha>: N resolved / M still apply / K could not be verified` | No, threads only | The three-way form. Only the `still apply` count asks for a code change; `could not be verified` means the agent was blocked from looking, which reads identically in the two-way form and is why it is split out |
| `ran a verification round on <sha> (mutate result: ...) but posted **nothing**` | No | Same escalation as the silent full review |
| `the verification round on <sha> was cancelled when the head moved to <newsha>, which is cancel-in-progress doing its job rather than a failure` | No | Benign. Nothing was re-checked, so treat the threads as un-re-checked and summon once after your last push |
| `the verification round on <sha> was cancelled before it posted a summary, and the head has not moved, so the cause is not recorded here` | No | Cause unknown by design rather than guessed. Some threads may have been replied to before it stopped; read the run log |
| `auto-paused after N automatic rounds at <sha> — re-request with @claude review` | No | Summon, or hand the pause back to whoever owns the PR; never wait for the next push. The text adds that an already-queued summon replaces this verdict when its round finishes |
| `paused by request at <sha>; resume with @claude resume` | No | Someone paused the lane deliberately. Resume only if that was you or you know why |
| `did not run at <sha>: the diff is below this repo's min_diff_lines floor` | No | No machine review on record. Summon if the diff deserves one anyway |
| `did not run at <sha>: the head moved during the debounce window, so this round would have reviewed a stale diff` | No | This head has no review. Whether the newer head gets one depends on its own run, which this round cannot see |
| `not reviewed at <sha>: the pull request is a draft, and nothing reviews a draft — summons included` | No | Mark it ready for review and the lane takes the whole diff in one round |
| `did not run at <sha>: neither CLAUDE_CODE_OAUTH_TOKEN nor ANTHROPIC_API_KEY reached this lane` | No | Both secrets are optional, so this covers secrets that are unset or empty as well as ones that never arrived. Set one on the repo or org. If a secret exists, check that the stub maps it explicitly: `secrets: inherit` does not cross owners |
| `no new commits since <sha> was last reviewed; nothing to re-review` | No | Nothing; the prior review stands |
| `did not run at <sha>: the push changed no line of this PR's own patch, so no round ran.` (`unchanged-patch`) | No, but the patch was | A rebase or restack whose patch matches `patch=` on the marker. The earlier review covers this content; summon only if the base change matters |
| `refused at <sha>: N reviewable line(s), above the ...` (`refused-size`) | No | The diff is over `max_reviewable_lines`. Split it into a stack, or `@claude full review` to override for one round |
| `finished on <sha> (job result: ...) and this job could not read back ...` (`counts-unread`) | Unknown | The round may have posted. Read the PR's `claude[bot]` threads before summoning again |
| `ran a verification round on <sha> and could not read back what it posted` (`verify-unread`) | No, threads only | Read the thread replies directly |
| `did not review <sha>: ...` (`api-error`) | No | The text names the class. `account-limit`: wait for the reset it names. `rate-limited` or `api-unavailable`: transient, summon again. `auth-failed`: an admin replaces the credential, retrying will not help. `billing`: fix billing, then summon. `model-unavailable`: pick an allowed `review.default_model`. `request-too-large`: split the PR or narrow `path_filters`. Any other error: read the run log. The job concludes `failure`, so read this text before assuming a code problem. A trailing sentence says whether findings were posted before the failure |
