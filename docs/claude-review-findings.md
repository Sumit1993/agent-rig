# Finding labels and parse contract

Every finding opens with a header line of three fields:

```
_<Category>_ | _<Severity>_ | _<Effort>_
```

Example: `_🎯 Functional Correctness_ | _🟠 Major_ | _⚡ Quick win_`

Ten labels across three dimensions:

| Dimension | Labels |
|---|---|
| Category | `Functional Correctness`, `Security & Privacy`, `Maintainability & Guidelines`, `Data Integrity & Integration`, `Stability & Availability` |
| Severity | `Critical`, `Major`, `Minor` |
| Effort | `Quick win`, `Heavy lift` |

- Field grammar `_[<emoji> ]<label>_`, fields separated by ` | `.
- Emoji are presentation only. Strip leading non-ASCII bytes, trim, exact-match the ASCII label. Never compare emoji bytes: two of the ten carry a U+FE0F variant selector and one is text-default.
- Unrecognised label: route to the fallback class `Major / Heavy lift` and log a parse notice. A finding is never dropped.
- Missing header (legacy comments): `Category: Functional Correctness`, `Severity: Major`, `Effort: Heavy lift`.
- The labels are the reviewer's own judgement and do not order the work. On `mage-memory#206` the three findings that together closed an unfinished schema were each `Quick win`, the one `Heavy lift` was adding a docs subsection, and the only `Security & Privacy` label sat on a superseded snapshot whose live section already routed through the scrubber. Parse the labels, then rank by reading the findings.
