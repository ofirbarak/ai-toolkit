## 3. Check each is worth reporting

Filter out: a flow so unlikely or unreliable that nobody will hit it, a flow nobody cares about, a small improvement that changes nothing for users or maintainers, a nitpick, a preference the repo doesn't document. When in doubt about a missing feature, a data-loss bug or a security bug, keep it.

## 4. Check against earlier review

Drop a flag a reviewer already raised on the PR and the author answered or fixed; it isn't news. Raise one yourself for a review thread marked resolved whose code didn't change and whose reply doesn't explain why — the comment was closed, not addressed.

If a previous review by this skill is given above, read it, and for every finding in it record **fixed** (with what fixed it), **still open**, or **no longer applies** (the code was removed or rewritten). Keep its IDs, number new findings after its highest, and don't re-raise a flag it ruled out unless the code under it changed.

## 5. Rate what's left

- **Blocker** — the mission isn't met (a missing feature, a broken main path), data is lost or corrupted, a security hole, or a production outage on a path real traffic takes.
- **Should fix** — a real bug on a less common path, a design choice that will cost the next change, a flow with no test where a regression would go unnoticed, a risky change that ships ungated or can't be rolled back, a failure in production nobody would be told about.
- **Extra** — everything else that is real but below that bar: a simpler design, a reuse, a clearer name, a minor gap. Extras go in the file only, never in the summary.

Give each kept finding an ID by subtask — `M1`, `D1`, `Q1`, `B1`, `T1`, `P1` — used in both parts below.

