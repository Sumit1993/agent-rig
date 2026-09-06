# Working in this repository

## Start at the tracker, not the issue list

`#56 - Tracker: state, direction and queue. Start here.` is pinned. Its **body** is the
current state and the queue; the comments are the log. If they disagree, the body wins.

```
gh issue view 56
```

Nineteen issues are open and the list carries no priority, so reading it cold produces
a plausible-looking wrong choice.

## Rulings live in comments

An issue body can be the superseded version of itself. Issues whose comments carry a
ruling that overrides part of the body are labelled `ruled`; read those comments before
acting on the body. Issues blocked on a decision only the operator can make are labelled
`needs-operator`.

## Quoting a number

Any figure taken from the transcript corpus names the corpus size and date range it came
from, or it does not get quoted. Figures drifted between runs here and could not be
diffed after the fact.
