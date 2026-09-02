# Incidents behind the rules

One paragraph per incident. A skill cites the slug; the story lives here so it stops loading on every turn. Add a paragraph when a rule is born from a failure, and keep the slug stable.

## stale-working-tree-seeds-canon-repo

An agy prompt told the lane to copy workflow files from another repo. The lane read the local checkout's working tree, which had been fetched but not pulled, so the files were pre-fix. The stale copies went into the canon repo and two consumer repos. A canary PR caught it. A fetch updates refs, not files, so reference content must come from `gh api` or `git show origin/main:<path>`.

## claude-kit-kill-destroys-prismalens-run

A test suite in claude-kit ran a name-wide kill against agy. It reaped a prismalens run mid-implementation on a release blocker. In that session it surfaced as rc=137 with an empty log, which looks like silent quota death, and the handler there spent its retry budget relaunching into a lane it believed was broken. agy processes carry no session or repo identity, so a kill by name reaches every session on the machine.

## gh-workflows-69-unwatched-pr

An agy lane opened gh-workflows PR #69. The review lane reviewed it automatically and nobody was watching, so the findings sat unread. A handler cannot hold a Monitor past its turn, so the fix is for the handler to put the PR URL in its report and for the main session to arm `pr-watch`.
