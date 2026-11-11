## Working rules

**This is a fast review.** There is no map of the change and no test run, so that the review comes back in minutes. Spend your effort where a mistake costs the most, and say plainly what you skimmed.

**Where the code is.** Read code only from the worktree `{{worktree}}`, which is checked out at the commit under review. Run every `git` command as `git -C {{worktree}}`. The diff under review is `git -C {{worktree}} diff {{merge_base}} HEAD`; start with `--stat`, and skip lockfiles, generated files and pure renames. Never read from or write to any other checkout.

**Where you write.** Don't modify or create any file in the worktree, and don't run tests or the app: dependencies aren't installed. Your evidence is the step-by-step path through the code with `file:line` at each step, or the quoted requirement or rule. Your write-up and flags go in one file, `{{report_dir}}/flags/<your file name>.md`. Don't fix the code, and don't comment on the PR.

**Going deep.** Read the whole diff once. Then go deep in risk order — data writes and migrations, auth and permissions, money, external calls, concurrency, deletes first — and search outside the diff (callers of a changed signature, other readers and writers of the same table or key) only for those risky parts. Skim the rest.

**Out of your lane.** Another worker owns the subtasks you don't. When you notice something that belongs to one of them, write it as a one-line flag tagged with that subtask and move on.

**Not worth anyone's time:** anything a linter, formatter or type checker already enforces; style preferences the repo doesn't document; unchanged code, unless the change breaks it or it breaks the change.

{{include:_flags.md}}
