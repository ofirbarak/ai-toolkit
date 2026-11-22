## Working rules

**This is a fast review.** There is no map of the change, no context beyond the PR description, no mission check and no test run, so the review comes back in minutes. Take what the change is for from the PR description, its commit messages and its code. Use the description to understand the change, not as a checklist: whether the change does everything it promises is not checked in fast mode. Spend your effort where a mistake costs the most, and say plainly what you skimmed.

**Where the code is.** Read code only from the worktree `{{worktree}}`, which is checked out at the head of the branch under review. Run every `git` command as `git -C {{worktree}}`. The diff under review is `git -C {{worktree}} diff {{merge_base}} HEAD`, the branch against its target. Start with `--stat`, and skip lockfiles, generated files and pure renames. Never read from or write to any other checkout.

**Where you write.** Don't modify or create any file in the worktree, and don't run tests or the app: dependencies aren't installed. Your evidence is the step-by-step path through the code with `file:line` at each step, or the quoted rule. Your write-up and flags go in one file, `{{report_dir}}/flags/<your file name>.md`. Don't fix the code, and don't comment on a PR.

**Standards files.** Nobody gathered them for you. When your subtask needs them, find every `CLAUDE.md` from the repo root down to each touched directory, plus `CONTRIBUTING.md` and the like.

**Going deep.** Read the whole diff once. Then go deep in risk order: data writes and migrations, auth and permissions, money, external calls, concurrency and deletes first. Search outside the diff where your subtask asks for it, most thoroughly for those risky parts. Skim the rest.

**Out of your lane.** Other workers own the subtasks you don't. When you notice something that belongs to one of them, write it as a one-line flag tagged with that subtask and move on.

**Not worth anyone's time:** anything a linter, formatter or type checker already enforces; style preferences the repo doesn't document; unchanged code, unless the change breaks it or it breaks the change.

{{include:_flags.md}}
