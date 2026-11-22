---
name: my-code-review
description: >-
  Use when the user wants a branch, a PR, or work-in-progress changes reviewed —
  "review this PR", "review my branch", "is this ready to merge", "check what I
  changed" — or wants an earlier review of the same PR or branch run again after
  fixes. Runs in normal mode by default, or fast mode ("fast", "quick review")
  for a quicker, lighter pass.
argument-hint: "[fast|normal] [PR number or branch]"
---

Five workers look for problems: mission, design, code quality, bugs-and-tests, and production. Bugs and tests share a worker because they read the same paths: whoever traces a path for a bug also asks which test would catch it. A judge decides which of their flags are worth the reader's time. The workers aim for recall, the judge for precision. Keeping them apart stops a reviewer from talking itself into its own findings.

Before the workers start, a mapper reads the whole change once and writes down what is there — the requirements, the areas, the resources touched and who else touches them — so every worker starts from the same facts, with the same IDs, and spends its effort judging.

## Mode

The first argument picks the mode: `fast` or `normal`. Anything else — a PR number, a branch, nothing at all — means `normal`, and the arguments that follow the mode name the target, a branch or a PR number: `/my-code-review fast my-branch`, `/my-code-review normal my-branch`, `/my-code-review 123`. No target means the current branch. Without arguments, a user who asks in words for a quick or fast review gets `fast`.

| | normal | fast |
|-|--------|------|
| Target | the head commit against its target, in a fresh worktree, with CI read and the changed lines counted | the head commit against its target (the PR's base, else the default branch), in a fresh worktree; nothing else |
| Context | PR, ticket, linked specs, review threads, stack, standards | the PR description only; no ticket, specs, review threads or stack; workers find the standards files themselves |
| Mission check | yes | no |
| Dependencies and tests | installed in the worktree; the PR's own tests are left to CI, and agents run only new tests they write to check what those don't cover | nothing installed or run; evidence is traced through the code |
| Mapper | yes | no |
| Workers | four or five in parallel: mission, design, quality, bugs-and-tests, production | three or four in parallel: design, quality, bugs-and-tests, production; each reads the code with no map and runs nothing |
| Judge | verifies by running the workers' new tests and reading | verifies by reading |

Steps 1–6 below describe `normal`. In `fast`, follow them with the changes in **Fast mode**.

## How the prompts are built

Every agent's prompt is a template in this skill's `prompts/` directory. A template is fixed text plus `{{slots}}`. Each step writes the slots the next step needs, as files in `<report-dir>/slots/<slot>.md`, and `assemble.py` fills the templates from them:

```bash
python3 <skill-dir>/assemble.py "$report" mapper
```

writes the finished prompt to `$report/prompts/mapper.md`. A template with a slot nobody has written is not assembled and the script exits 1 — write the slot, then run it again. `<skill-dir>` is this skill's base directory.

Spawn every agent as a fresh `general-purpose` agent whose whole prompt is:

> You are the `<role>` of a code review. Your full brief is in `<report-dir>/prompts/<template>.md`. Read all of it before doing anything else, then follow it.

The prompts stay in the report directory, so you can see exactly what each agent was told.

| Slot | Written in | What goes in it | Read by |
|------|-----------|-----------------|---------|
| `worktree` | 1 | The worktree's absolute path, alone | all |
| `merge_base` | 1 | The merge-base commit, alone | mapper |
| `target` | 1 | The PR number and title or the branch; the head commit; the base ref and the merge-base; the diff command `git -C <worktree> diff <merge-base> HEAD`; the commits (`git -C <worktree> log --oneline <merge-base>..HEAD`); the changed-line count | all |
| `test_setup` | 1 | The PR's CI checks and their state at the head commit (or "No CI run."), and the command to run a single test file — or why tests can't run here, so every agent traces paths instead | mapper, mission, bugs-tests, production, judge |
| `mission` | 2 | Verbatim: the PR description, the linked ticket, and the paths of the specs, plans and design docs they point to — or the user's own words | all |
| `standards` | 2 | The paths of every `CLAUDE.md` from the root down to each touched directory, `CONTRIBUTING.md`, a glossary, and the like | mapper, design, quality, production, judge |
| `stack` | 2 | Each related PR — below this one or built on it — and what it changes; or "Not stacked." | mapper, design, bugs-tests, production, judge |
| `prior_review` | 2 | The PR's review threads with their resolved state; or "None." | judge only |
| `previous_head` | 2 | The head of the previous review of this PR or branch; or "None." | mapper, workers |
| `previous_review` | 2 | The path of the previous `review.md`; or "None." | judge only |
| `focus_mission`, `focus_design`, `focus_quality`, `focus_bugs_tests`, `focus_production` | 3, by the mapper | Where that worker should start, generated from the map | that worker |
| `shape` | 4 | Which workers ran, which were skipped and why, and any worker that failed | judge |
| `report_dir` | — | Filled in by the script | all |

`prior_review` and `previous_review` go to the judge only, so the workers look with fresh eyes.

Fast mode writes only `worktree`, `merge_base`, `target`, `mission` (the PR description alone), `previous_head`, `previous_review` and `shape`.

## 1. Pin the target

Every agent must read the same code: the commit under review, not whatever happens to be checked out.

1. **Resolve the head commit and the base** from what the user named:
   - **A PR number:** `gh pr view <n> --json headRefOid,baseRefName,headRefName,title,body`, then `git fetch origin pull/<n>/head <baseRefName>`. The head is `headRefOid`; the base is `origin/<baseRefName>`.
   - **A branch or ref:** `git fetch origin`, then the head is `git rev-parse <ref>` and the base is the default branch (`origin/HEAD`). If the branch has an open PR (`gh pr view <branch>`), use its base and description instead.
   - **Nothing:** the current branch, resolved the same way.
2. **Stop early** if the head doesn't resolve, or if `git diff --quiet $(git merge-base <base> <head>) <head>` exits 0: there is nothing to review. Say which, and spawn nothing. Uncommitted changes are not reviewed; if the user wants work in progress reviewed, say so and have them commit it first.
3. **Create the worktree and the report directory:**

   ```bash
   stamp="$(git rev-parse --short <head>)-$(date +%Y%m%d-%H%M%S)"
   wt="${TMPDIR:-/tmp}/code-review-$stamp"
   report="$wt-report"
   git worktree add --detach "$wt" <head>
   mkdir -p "$report"/{slots,flags,evidence}
   ```

   The report directory sits outside the worktree, so it survives the cleanup.
4. **Make it runnable.** A fresh worktree has no installed dependencies or build output. Set it up the way the repo says to (its README, Makefile or `CLAUDE.md`: `npm ci`, `uv sync`, `make install` and the like), or link the main checkout's dependency directories when the lockfiles match. The setup is only for the new tests the agents write to check what the PR's tests don't cover; don't run the PR's own tests or the suite — CI does that. Confirm the setup by running one existing test file. If tests can't run here — they need services or credentials you don't have — that goes in `test_setup`, and the report says so.
5. **Read CI.** For a PR, `gh pr checks <n>`; for a branch, the checks on its head commit. Take CI's result as the verdict on the PR's own tests. A failing or pending check goes in `test_setup`, and the report says so.
6. **Count the changed lines**, without lockfiles and generated files, for `target` and the worker shape.
7. **Write** `worktree`, `merge_base`, `target` and `test_setup`.

## 2. Gather the context

1. **The mission.** The PR description, the linked issue or ticket (Linear, GitHub), and every spec, plan or design doc they point to. If none of these exist, ask the user what the change is meant to do before going on; the mission worker has nothing to check against without it.
2. **Earlier review on the PR:** its review threads with their resolved state (`gh pr view <n> --comments`, and the inline ones from `gh api repos/{owner}/{repo}/pulls/<n>/comments`).
3. **The stack:** whether this PR's base isn't the default branch, or other PRs build on it (`gh pr list --base <headRefName>`), and what each related PR changes.
4. **The standards files** that cover the touched files.
5. **A previous review by this skill** — see **Re-review**.

Write `mission`, `standards`, `stack`, `prior_review`, `previous_head` and `previous_review`. Write "None." into a slot that has nothing; an empty slot file still counts as written.

## 3. Map the change

```bash
python3 <skill-dir>/assemble.py "$report" mapper
```

Spawn the mapper and wait for it. It writes `$report/context.md`, the five `focus_*` slots, and `$report/flags/mapper.md`. If it reports a spec it couldn't open, get it for the mapper — ask the user if you must — and spawn it again.

## 4. Run the workers

Pick the shape from the changed-line count:

- **Under ~50 lines:** mission, quality, bugs-tests, production. Skip design.
- **~50 lines and up:** all five. Never run more than five.

Skip production only when the change can't reach a running system — docs, comments, or tests alone — and say so in `shape`.

Write `shape`, then assemble the workers in the shape and spawn them all in one message — they own different subtasks and don't need each other:

```bash
python3 <skill-dir>/assemble.py "$report" mission design quality bugs-tests production
```

Each worker writes `$report/flags/<worker>.md` (`mission.md`, `design.md`, `quality.md`, `bugs-tests.md`, `production.md`) and answers with a one-line-per-flag list. When they have all returned, check every worker in the shape left its flags file. Spawn a worker that didn't once more with the same prompt; if it fails again, add that to `shape`.

## 5. Run the judge

```bash
python3 <skill-dir>/assemble.py "$report" judge
```

Spawn the judge. It reads the map and every flags file itself — don't relay the workers' answers to it; they are summaries, and the files hold the evidence. The workers are done with the worktree, so the judge can run the tests they wrote and write its own there; nothing touches the user's checkout. It writes `$report/review.md` and answers with the summary.

## 6. Report

Open with the judge's summary as it is. End with the absolute path to `$report/review.md`, for the evidence, the full review and the extras. Then remove the worktree: `git worktree remove --force "$wt"`. The evidence is already copied out.

## Fast mode

A quick pass over a branch against its target. Say at the start that this is a fast review. It skips the rest of pinning the target (installing dependencies, CI), most of gathering the context, the mission check and the mapper. Of the context, it reads only the PR description: no ticket, spec or review thread.

1. **Resolve the branch, its target and its PR description.**
   - **A PR number:** `gh pr view <n> --json headRefOid,headRefName,baseRefName,title,body`, then `git fetch origin pull/<n>/head <baseRefName>`.
   - **A branch:** its target is its open PR's base (`gh pr view <branch> --json number,baseRefName,title,body`), or the default branch (`origin/HEAD`) when it has no PR. Run `git fetch origin <branch> <target>`; a branch that exists only locally needs no fetch of its own.
   - **Nothing:** the current branch, resolved the same way. Uncommitted changes are not reviewed.

   Then create the worktree and the report directory, with nothing installed:

   ```bash
   merge_base="$(git merge-base origin/<target> <head>)"
   stamp="$(git rev-parse --short <head>)-$(date +%Y%m%d-%H%M%S)"
   wt="${TMPDIR:-/tmp}/code-review-$stamp"
   report="$wt-fast-report"
   git worktree add --detach "$wt" <head>
   mkdir -p "$report"/{slots,flags}
   ```

   Stop early, spawning nothing, if the head doesn't resolve or `git diff --quiet "$merge_base" <head>` exits 0.
2. **Write the slots:**
   - `worktree`: the worktree's path, alone;
   - `merge_base`: the merge-base commit, alone;
   - `target`: the branch (and PR number, if any), the head commit, the target branch and the merge base; the diff command `git -C <worktree> diff <merge-base> HEAD`; the commits (`git -C <worktree> log --oneline <merge-base>..HEAD`); and the changed-line count, without lockfiles and generated files;
   - `mission`: the PR's title and description, verbatim. If there is no PR, write "No PR: take what the change is for from its commit messages.";
   - `previous_head` and `previous_review`: see **Re-review**, or "None.".
3. **Run the workers:** design, quality, bugs-tests and production, the same subtasks as normal mode without mission. Pick the shape the same way as normal mode: skip design under ~50 changed lines, and skip production when the change can't reach a running system. Write `shape` (for example `fast: design, quality, bugs-tests, production`), then assemble the workers in the shape and spawn them all in one message:

   ```bash
   python3 <skill-dir>/assemble.py "$report" fast-design fast-quality fast-bugs-tests fast-production
   ```

   Each writes `$report/flags/<worker>.md` (`design.md`, `quality.md`, `bugs-tests.md`, `production.md`). Retry a worker that left no file once, as in normal mode.
4. **Run the judge** from `fast-judge`:

   ```bash
   python3 <skill-dir>/assemble.py "$report" fast-judge
   ```

5. **Report:** open with the judge's summary as it is, end with the path to `$report/review.md`, then remove the worktree with `git worktree remove --force "$wt"`. Offer a normal review when the fast one leaves a finding marked **unverified**, when the change is over ~1,000 lines, or when the user needs to know whether it meets its mission.

## Re-review

When the user asks to review the same PR or branch again, usually after fixing findings:

1. **Find the previous review:** the newest `${TMPDIR:-/tmp}/code-review-*-report/review.md` whose header names the same PR or branch, in either mode. If there is none, or more than one could fit, ask the user for its path.
2. **Write** its head commit, from its header, into `previous_head`, and its path into `previous_review`. The mapper then maps what changed since, the workers read that diff closely — fixes are where new bugs come from — and the judge gives each earlier finding a status before the new ones.
3. **Run the review as usual**, in the mode the user asked for this time, with a new report directory (and, in normal mode, a new worktree).

## Changing a prompt

Change the template in `prompts/`, never an assembled prompt in a report directory. The rules every worker shares — where to read and write, running tests alongside other workers, the flag format, what isn't worth flagging — live once, in `prompts/_worker-rules.md`, which each worker template includes with `{{include:_worker-rules.md}}`. Includes can nest. The parts both modes share live once too: the flag format in `_flags.md` (included by `_worker-rules.md` and `_fast-worker-rules.md`), and the judge's filter and ratings in `_judge-filter.md` (included by `judge.md` and `fast-judge.md`). A new slot needs a row in the table above, saying which step writes it.
