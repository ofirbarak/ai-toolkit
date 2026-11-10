---
name: my-code-review
description: >-
  Use when the user wants a branch, a PR, or work-in-progress changes reviewed —
  "review this PR", "review my branch", "is this ready to merge", "check what I
  changed" — or wants an earlier review of the same PR or branch run again after
  fixes.
---

Five workers look for problems, each owning one subtask — mission, design, code quality, bugs, tests — and a judge decides which of their flags are worth the reader's time. The workers aim for recall, the judge for precision. Keeping them apart stops a reviewer from talking itself into its own findings.

Before the workers start, a mapper reads the whole change once and writes down what is there — the requirements, the areas, the resources touched and who else touches them — so every worker starts from the same facts, with the same IDs, and spends its effort judging.

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
| `test_setup` | 1 | The commands to run one test, one package's tests, and a package's tests with coverage — or why tests can't run here, so every agent traces paths instead | mapper, mission, bugs, tests, judge |
| `mission` | 2 | Verbatim: the PR description, the linked ticket, and the paths of the specs, plans and design docs they point to — or the user's own words | all |
| `standards` | 2 | The paths of every `CLAUDE.md` from the root down to each touched directory, `CONTRIBUTING.md`, a glossary, and the like | mapper, design, quality, judge |
| `stack` | 2 | Each related PR — below this one or built on it — and what it changes; or "Not stacked." | mapper, design, bugs, judge |
| `prior_review` | 2 | The PR's review threads with their resolved state; or "None." | judge only |
| `previous_head` | 2 | The head of the previous review of this PR or branch; or "None." | mapper, workers |
| `previous_review` | 2 | The path of the previous `review.md`; or "None." | judge only |
| `focus_mission`, `focus_design`, `focus_quality`, `focus_bugs`, `focus_tests` | 3, by the mapper | Where that worker should start, generated from the map | that worker |
| `shape` | 4 | Which workers ran, which were skipped and why, and any worker that failed | judge |
| `report_dir` | — | Filled in by the script | all |

`prior_review` and `previous_review` go to the judge only, so the workers look with fresh eyes.

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
4. **Make it runnable.** A fresh worktree has no installed dependencies or build output. Set it up the way the repo says to (its README, Makefile or `CLAUDE.md`: `npm ci`, `uv sync`, `make install` and the like), or link the main checkout's dependency directories when the lockfiles match. Run one existing test to confirm. If the suite can't run here — it needs services or credentials you don't have — that goes in `test_setup`, and the report says so.
5. **Count the changed lines**, without lockfiles and generated files, for `target` and the worker shape.
6. **Write** `worktree`, `merge_base`, `target` and `test_setup`.

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

- **Under ~50 lines:** mission, quality, bugs, tests. Skip design.
- **~50 lines and up:** all five. Never run more than five.

Write `shape`, then assemble the workers in the shape and spawn them all in one message — they own different subtasks and don't need each other:

```bash
python3 <skill-dir>/assemble.py "$report" mission design quality bugs tests
```

Each worker writes `$report/flags/<subtask>.md` and answers with a one-line-per-flag list. When they have all returned, check every worker in the shape left its flags file. Spawn a worker that didn't once more with the same prompt; if it fails again, add that to `shape`.

## 5. Run the judge

```bash
python3 <skill-dir>/assemble.py "$report" judge
```

Spawn the judge. It reads the map and every flags file itself — don't relay the workers' answers to it; they are summaries, and the files hold the evidence. The workers are done with the worktree, so the judge can run their tests and write its own there; nothing touches the user's checkout. It writes `$report/review.md` and answers with the summary.

## 6. Report

Open with the judge's summary as it is. End with the absolute path to `$report/review.md`, for the evidence, the full review and the extras. Then remove the worktree: `git worktree remove --force "$wt"`. The evidence is already copied out.

## Re-review

When the user asks to review the same PR or branch again, usually after fixing findings:

1. **Find the previous review:** the newest `${TMPDIR:-/tmp}/code-review-*-report/review.md` whose header names the same PR or branch. If there is none, or more than one could fit, ask the user for its path.
2. **Write** its head commit, from its header, into `previous_head`, and its path into `previous_review`. The mapper then maps what changed since, the workers read that diff closely — fixes are where new bugs come from — and the judge gives each earlier finding a status before the new ones.
3. **Run steps 1–6 as usual**, in a new worktree and report directory.

## Changing a prompt

Change the template in `prompts/`, never an assembled prompt in a report directory. The rules every worker shares — where to read and write, running tests alongside other workers, the flag format, what isn't worth flagging — live once, in `prompts/_worker-rules.md`, which each worker template includes with `{{include:_worker-rules.md}}`. A new slot needs a row in the table above, saying which step writes it.
