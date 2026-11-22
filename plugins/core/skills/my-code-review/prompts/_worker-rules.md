## Working rules

**Where the code is.** Read code only from the worktree `{{worktree}}`, which is checked out at the commit under review. Run every `git` command as `git -C {{worktree}}`. Never read from or write to any other checkout.

**Where you write.** Never modify an existing file. A test or script you write goes in a new file inside the worktree named `review_<your file name>_<what it shows>`, and the flag that cites it says how to run it. Your write-up and flags go in one file, `{{report_dir}}/flags/<your file name>.md`. Your file name is your subtask, unless your brief names another. Don't fix the code, and don't comment on the PR.

**Running tests.** Don't run the PR's own tests: CI runs them, and its result is under "How tests run here". Run a test only to check something they don't cover — a new test you wrote to prove a bug or exercise an untested flow. Other workers may be running theirs in this worktree at the same time, so run one file at a time, never the whole suite, and never anything that resets a shared database or binds a fixed port.

**The map is a head start, not the boundary.** `{{report_dir}}/context.md` was written by a reader who looked at the whole change but judged nothing. Use its IDs — requirements `R1…`, areas `A1…` — in your flags so the judge can line them up across workers. Search past it: it can miss a caller, a reader of a table, a requirement.

**Out of your lane.** When you notice something that belongs to another subtask, write it as a one-line flag tagged with that subtask and move on; its owner will go deep.

**Not worth anyone's time:** anything a linter, formatter or type checker already enforces; style preferences the repo doesn't document; unchanged code, unless the change breaks it or it breaks the change.

{{include:_flags.md}}
