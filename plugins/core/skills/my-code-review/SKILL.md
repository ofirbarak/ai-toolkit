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

Six workers look for problems, each owning one subtask — mission, design, code quality, bugs, tests, production — and a judge decides which of their flags are worth the reader's time. The workers aim for recall, the judge for precision. Keeping them apart stops a reviewer from talking itself into its own findings.

Before the workers start, a mapper reads the whole change once and writes down what is there — the requirements, the areas, the resources touched and who else touches them — so every worker starts from the same facts, with the same IDs, and spends its effort judging.

## Mode

The first argument picks the mode: `fast` or `normal`. Anything else — a PR number, a branch, nothing at all — means `normal`, and the arguments that follow the mode name the target: `/my-code-review fast 123`, `/my-code-review normal my-branch`, `/my-code-review 123`. Without arguments, a user who asks in words for a quick or fast review gets `fast`.

| | normal | fast |
|-|--------|------|
| Context | PR, ticket, linked specs, review threads, stack, standards | PR and ticket, review threads, standards; no specs or stack |
| Dependencies and tests | installed in the worktree; the PR's own tests are left to CI, and agents run only new tests they write to check what those don't cover | not installed; nothing runs, evidence is traced through the code |
| Mapper | yes | no |
| Workers | five or six, one per subtask | two in parallel: correctness (mission, bugs) and maintainability (design, quality, tests, production) |
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
| `test_setup` | 1 | The PR's CI checks and their state at the head commit (or "No CI run."), and the command to run a single test file — or why tests can't run here, so every agent traces paths instead | mapper, mission, bugs, tests, production, judge |
| `mission` | 2 | Verbatim: the PR description, the linked ticket, and the paths of the specs, plans and design docs they point to — or the user's own words | all |
| `standards` | 2 | The paths of every `CLAUDE.md` from the root down to each touched directory, `CONTRIBUTING.md`, a glossary, and the like | mapper, design, quality, production, judge |
| `stack` | 2 | Each related PR — below this one or built on it — and what it changes; or "Not stacked." | mapper, design, bugs, production, judge |
| `prior_review` | 2 | The PR's review threads with their resolved state; or "None." | judge only |
| `previous_head` | 2 | The head of the previous review of this PR or branch; or "None." | mapper, workers |
| `previous_review` | 2 | The path of the previous `review.md`; or "None." | judge only |
| `focus_mission`, `focus_design`, `focus_quality`, `focus_bugs`, `focus_tests`, `focus_production` | 3, by the mapper | Where that worker should start, generated from the map | that worker |
| `shape` | 4 | Which workers ran, which were skipped and why, and any worker that failed | judge |
| `report_dir` | — | Filled in by the script | all |

`prior_review` and `previous_review` go to the judge only, so the workers look with fresh eyes.

In fast mode, `test_setup`, `stack` and the `focus_*` slots aren't written: the fast workers read `worktree`, `merge_base`, `target`, `mission` and `previous_head`, the maintainability worker also `standards`, and the fast judge `standards`, `prior_review`, `shape` and `previous_review` as well.

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

Spawn the mapper and wait for it. It writes `$report/context.md`, the six `focus_*` slots, and `$report/flags/mapper.md`. If it reports a spec it couldn't open, get it for the mapper — ask the user if you must — and spawn it again.

## 4. Run the workers

Pick the shape from the changed-line count:

- **Under ~50 lines:** mission, quality, bugs, tests, production. Skip design.
- **~50 lines and up:** all six. Never run more than six.

Skip production only when the change can't reach a running system — docs, comments, or tests alone — and say so in `shape`.

Write `shape`, then assemble the workers in the shape and spawn them all in one message — they own different subtasks and don't need each other:

```bash
python3 <skill-dir>/assemble.py "$report" mission design quality bugs tests production
```

Each worker writes `$report/flags/<subtask>.md` and answers with a one-line-per-flag list. When they have all returned, check every worker in the shape left its flags file. Spawn a worker that didn't once more with the same prompt; if it fails again, add that to `shape`.

## 5. Run the judge

```bash
python3 <skill-dir>/assemble.py "$report" judge
```

Spawn the judge. It reads the map and every flags file itself — don't relay the workers' answers to it; they are summaries, and the files hold the evidence. The workers are done with the worktree, so the judge can run the tests they wrote and write its own there; nothing touches the user's checkout. It writes `$report/review.md` and answers with the summary.

## 6. Report

Open with the judge's summary as it is. End with the absolute path to `$report/review.md`, for the evidence, the full review and the extras. Then remove the worktree: `git worktree remove --force "$wt"`. The evidence is already copied out.

## Fast mode

The same steps, trimmed for speed. Say at the start that this is a fast review.

1. **Pin the target** as usual, but skip step 1.4: don't install dependencies or run a test. Name the report directory `code-review-<stamp>-fast-report`, so a later review can tell the modes apart.
2. **Gather the context** without the specs and docs the PR or ticket links to, and without the stack. Read the PR description and the linked ticket, the review threads, and the standards files. If there is no mission, take it from the commit messages rather than asking the user, and say so in `mission`. Write `mission`, `standards`, `prior_review`, `previous_head` and `previous_review`.
3. **Skip the mapper.**
4. **Run two workers**, whatever the size of the change. Write `shape` (`fast: correctness, maintainability`), then assemble and spawn both in one message:

   ```bash
   python3 <skill-dir>/assemble.py "$report" fast-correctness fast-maintainability
   ```

   They write `$report/flags/correctness.md` and `$report/flags/maintainability.md`. Retry a worker that left no file once, as in normal mode.
5. **Run the judge** from `fast-judge`:

   ```bash
   python3 <skill-dir>/assemble.py "$report" fast-judge
   ```

6. **Report** as usual, and end by offering a normal review when the fast one leaves a finding marked **unverified**, or when the change is over ~1,000 lines.

## Re-review

When the user asks to review the same PR or branch again, usually after fixing findings:

1. **Find the previous review:** the newest `${TMPDIR:-/tmp}/code-review-*-report/review.md` whose header names the same PR or branch, in either mode. If there is none, or more than one could fit, ask the user for its path.
2. **Write** its head commit, from its header, into `previous_head`, and its path into `previous_review`. The mapper then maps what changed since, the workers read that diff closely — fixes are where new bugs come from — and the judge gives each earlier finding a status before the new ones.
3. **Run steps 1–6 as usual**, in the mode the user asked for this time, in a new worktree and report directory.

## Changing a prompt

Change the template in `prompts/`, never an assembled prompt in a report directory. The rules every worker shares — where to read and write, running tests alongside other workers, the flag format, what isn't worth flagging — live once, in `prompts/_worker-rules.md`, which each worker template includes with `{{include:_worker-rules.md}}`. Includes can nest. The parts both modes share live once too: the flag format in `_flags.md` (included by `_worker-rules.md` and `_fast-worker-rules.md`), and the judge's filter and ratings in `_judge-filter.md` (included by `judge.md` and `fast-judge.md`). A new slot needs a row in the table above, saying which step writes it.
