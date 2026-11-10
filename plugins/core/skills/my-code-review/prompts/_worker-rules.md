## Working rules

**Where the code is.** Read code only from the worktree `{{worktree}}`, which is checked out at the commit under review. Run every `git` command as `git -C {{worktree}}`. Never read from or write to any other checkout.

**Where you write.** Never modify an existing file. A test or script you write goes in a new file inside the worktree named `review_<your subtask>_<what it shows>`, and the flag that cites it says how to run it. Your write-up and flags go in one file, `{{report_dir}}/flags/<your subtask>.md`. Don't fix the code, and don't comment on the PR.

**Running tests.** Other workers are running tests in this worktree at the same time. Run only the tests you target, one file or test at a time, never the whole suite (the tests worker is the only exception), and never anything that resets a shared database or binds a fixed port.

**The map is a head start, not the boundary.** `{{report_dir}}/context.md` was written by a reader who looked at the whole change but judged nothing. Use its IDs — requirements `R1…`, areas `A1…` — in your flags so the judge can line them up across workers. Search past it: it can miss a caller, a reader of a table, a requirement.

**Out of your lane.** When you notice something that belongs to another subtask, write it as a one-line flag tagged with that subtask and move on; its owner will go deep.

**Not worth anyone's time:** anything a linter, formatter or type checker already enforces; style preferences the repo doesn't document; unchanged code, unless the change breaks it or it breaks the change.

## Flags

Raise flags, not verdicts. Aim for recall: keep a flag you are unsure of and say so, because the judge decides what is real and worth reporting. Drop a flag you can't give evidence for.

Number your flags with your subtask's lowercase letter — `m1`, `d1`, `q1`, `b1`, `t1` — and write each one in exactly this shape:

```markdown
### b3: <the problem in one line>
- **Subtask:** bugs
- **Where:** `path/to/file.py:120` — or `missing: <what isn't there>`
- **Relates to:** R2, A4 — or "none"
- **What is wrong:** <two or three sentences>
- **Why it matters:** <who or what notices, and when>
- **Evidence:** <one of: the test file, the command that runs it, and what it printed; the step-by-step path through the code with file:line at each step; the quoted requirement or rule>
- **Confidence:** high | medium | low — <what would settle it>
```

## When you finish

Your flags file holds, in order: the write-up your subtask asks for (if any), then every flag. Your answer to whoever started you is only this: how many flags you raised, then one line per flag — its number, confidence, and the one-line problem. Everything else is in the file.
