---
name: my-code-review
description: >-
  Review changed code with five workers and a judge. Each worker owns one
  subtask: whether the change fulfils its mission (requirements vs. code,
  missing features), its design and architecture, code quality, bugs (with a
  proof for each, including flows and third parties that touch the same code
  or data), and tests. The judge filters their flags down to what is real and
  worth acting on, and reports one short line per blocker and should-fix plus
  a file with the evidence, the full review and the minor extras. Use when the user wants to review a branch, a
  PR, or work-in-progress changes.
---

Five workers look for problems, each owning one subtask, and a judge decides which of their flags are worth the reader's time. The workers aim for recall, the judge for precision. Keeping them apart stops a reviewer from talking itself into its own findings.

## 1. Pin the target

Every agent must read the same code: the commit under review, not whatever happens to be checked out.

1. **Resolve the head commit and the base** from what the user named:
   - **A PR number:** `gh pr view <n> --json headRefOid,baseRefName,headRefName,title,body`, then `git fetch origin pull/<n>/head <baseRefName>`. The head is `headRefOid`; the base is `origin/<baseRefName>`.
   - **A branch or ref:** `git fetch origin`, then the head is `git rev-parse <ref>` and the base is the default branch (`origin/HEAD`). If the branch has an open PR (`gh pr view <branch>`), use its base and description instead.
   - **Nothing:** the current branch, resolved the same way.
2. **Stop early** if the head doesn't resolve, or if `git diff --quiet $(git merge-base <base> <head>) <head>` exits 0: there is nothing to review. Say which, and spawn nothing.
3. **Create one worktree** at the head commit:

   ```bash
   wt="${TMPDIR:-/tmp}/code-review-$(git rev-parse --short <head>)"
   git worktree add --detach "$wt" <head>
   ```

4. **Make it runnable.** A fresh worktree has no installed dependencies or build output, so nothing in it can run tests yet. Set it up the way the repo says to (its README, Makefile or `CLAUDE.md`: `npm ci`, `uv sync`, `make install` and the like), or link the main checkout's dependency directories when the lockfiles match. Run one existing test to confirm. If the suite can't run here — it needs services or credentials you don't have — note that; every agent then traces paths instead of running tests, and the report says so.

The diff to review is `git -C "$wt" diff <merge-base> HEAD`. Uncommitted changes are not in the worktree; if the user wants work in progress reviewed, say so and have them commit it first.

## 2. Gather the context

Before spawning anything, collect:

- **The mission.** What this change is supposed to achieve: the PR description, the linked issue or ticket (Linear, GitHub), and any spec, plan or design doc the PR or ticket points to. If none of these exist, ask the user what the change is meant to do before going on; the mission worker has nothing to check against without it.
- The diff and the commits (`git -C "$wt" log --oneline <merge-base>..HEAD`), and the PR discussion if there is a PR.
- **Earlier review.** The PR's review threads with their resolved state (`gh pr view <n> --comments`, and the inline ones from `gh api repos/{owner}/{repo}/pulls/<n>/comments`). They go to the judge, not the workers, so the workers look with fresh eyes.
- **The stack.** Whether this PR is one of a stack: its base isn't the default branch, or other PRs build on it (`gh pr list --base <headRefName>`). Note each related PR and what it changes.
- The repo's standards files that cover the touched files: `CLAUDE.md` files from the root down to each touched directory, `CONTRIBUTING.md` and the like.

Each sub-agent knows only its prompt, so paste in: the worktree path, with the rule to read code only from there and run every `git` command as `git -C <worktree>`; the diff command, the commits, the mission, the PR discussion, the stack, the standards files' paths, the worker's or judge's brief below, and **Where not to spend effort**. Workers and the judge are fresh `general-purpose` agents.

## 3. Run the workers

Spawn the workers in one message; they own different subtasks and don't need each other. Never run more than five. Scale down for a small change, counting changed lines without lockfiles and generated files:

- **Under ~50 lines:** skip the design worker (3.2) and fold the tests worker's brief (3.5) into the bugs worker's (3.4). Three workers.
- **~50 lines and up:** all five. On a very large change (over ~1,000 lines), tell the bugs worker to rank the areas of the change by risk — data writes, auth, external calls, migrations first — and go deep on those rather than skim everything.

Say in the report which shape ran.

Every worker's prompt ends with the same rules:

Raise flags, not verdicts. For each flag: the subtask, `file:line` (or "missing" for something that isn't there), what is wrong, why it matters, and the evidence — the scenario, test, trace or quoted requirement that shows it. Keep a flag you're unsure of; the judge decides whether it is real and worth reporting. Drop one you can't give evidence for. Never modify existing files; a test or script you write goes in a new file named `review_<subtask>_*` inside the worktree, and you say in the flag how to run it. Other workers are running tests in this worktree at the same time: run only the tests you target, one file or test at a time, never the whole suite, and don't run anything that resets a shared database or binds a fixed port. Only the tests worker runs the full suite.

### 3.1 Mission

Does this change do what it was asked to do?

1. **Break the mission into requirements.** List every requirement the mission states or clearly implies: features, behaviours, constraints, acceptance criteria, edge cases called out in the ticket or spec.
2. **Map each requirement to the code** that implements it (`file:line`), or mark it missing. Flag every requirement that is not implemented at all — a whole missing feature is the most important flag this worker can raise — and every one implemented only partly, or differently from what was asked.
3. **Check the implemented parts cover the mission end to end.** Follow the main path a user or caller takes, from entry point to stored result or response. Flag a step that is stubbed, hard-coded, behind a flag nobody turns on, or not wired into the entry point.
4. **Flag scope drift**: code the mission didn't ask for.

Return the requirement-to-code map along with the flags.

### 3.2 Design and architecture

First, build the design from the code, top down, and write it out: the entry points, the components the change adds or touches, the data it reads and writes, and the flow from request to result. Then place it in the system: which existing flows this change plugs into or interferes with, and what each of them looks like before and after the change.

Then judge the design on:

1. **Simplicity.** Is this the simplest design that meets the mission? Could a layer, abstraction, table, service or config be dropped?
2. **Extend, don't add.** Is there an existing flow, component, table or extension point this should have extended instead of building a parallel one?
3. **Blast radius.** How much of the system does the change touch, and could it touch less? What else breaks or has to change if this design is wrong?
4. **Generality.** Is it generic where the next similar feature will need it, without speculative generality for needs nobody has?
5. **Resilience.** What happens when a dependency is slow, down, or returns garbage; on retries, duplicates, partial failures, and restarts mid-flow?
6. **Boundaries and ownership.** Is each responsibility in one place, in the module that owns that concept? Are the interfaces between parts narrow?
7. **Operability and evolution.** Can it be rolled out and rolled back safely (migrations, flags, backward-compatible formats)? Can it be observed?

Finish with how you would design it, if differently, and what that would save. Return the written design along with the flags; the judge needs it as context.

### 3.3 Code quality

1. **Reuse.** For every new function, class, helper, constant, type, query, component, script or config block, search for whether it already exists: in this repo (search by what it does, not only its name; also catch a copied block that should call or extract the original), in what the repo already depends on (standard library, framework, installed packages), or, when the hand-rolled version is non-trivial, in a common maintained library. Flag only a fit with the same behaviour, edge cases and errors included, that would be simpler than what was written.
2. **Dead code.** Code the change adds or leaves behind that nothing calls: unused functions, parameters, branches, flags, imports, config keys.
3. **Comments and docs.** Too many: comments that restate the code, narrate the change, or carry ticket IDs. Wrong: a comment or doc the change made stale. Missing: a `CLAUDE.md`, README, API doc or runbook that should have changed with the code and didn't.
4. **Names.** A name that doesn't say what it does or holds, or a domain term the repo already has a different word for.
5. **Simplicity.** Deep nesting, long functions doing several things, clever code where plain code would do.
6. **Standards.** Every rule in the standards files the diff breaks, quoting the rule.
7. **Smells**, always judgement calls, and overridden by a documented standard: Duplicated Code, Feature Envy, Data Clumps, Primitive Obsession, Repeated Switches, Shotgun Surgery, Divergent Change, Speculative Generality, Message Chains, Middle Man, Refused Bequest.

### 3.4 Bugs

Find what the code does not handle, and prove each one: a test that fails on the current code, or, when a test needs production infrastructure, timing or a third party you can't stand up, the exact input or sequence of events and the step-by-step path through the code.

1. **Inside the change.** The main path doing the wrong thing; edge cases (empty, null/None, zero, very large, duplicate, unicode, first-run and retry inputs); wrong or inverted conditions, off-by-one, a missed case; partial writes with no rollback; stale caches or derived values; a migration or format change that breaks existing data; security (unvalidated input reaching a query, shell, path, template or redirect, a missing auth or ownership check, a secret returned to a caller); leaks, unbounded growth, N+1 queries, blocking calls on a hot path.
2. **Callers and the stack.** A changed signature, return shape, default or API response that unchanged code still relies on — search for every caller, the diff won't show them. What this PR needs from the PRs below it, and what the PRs above expect from it.
3. **Other flows on the same code and data.** List every table, key, queue, file, cache and external resource the change reads or writes, then search for everything else that touches them: other writers, readers that assume the old shape or meaning, background jobs, scheduled tasks, retries, concurrent requests. A table this change writes that another service reads is in scope.
4. **Third parties.** The database (constraints, triggers, locks, isolation level), queues, external APIs, and anything else whose behaviour the change assumes. Check the assumption against how it actually behaves.
5. **Failure paths.** Walk every way the changed code can fail and follow what happens next: an error swallowed or turned into a misleading default, an operation left half done, a failure nobody would notice or could diagnose from the logs.

### 3.5 Tests

1. **Meaningful tests.** Do the tests assert the behaviour the mission asks for, through the public surface? Flag a test that would still pass if the change were wrong, one that only checks a mock was called, or one that pins incidental detail.
2. **Coverage.** You are the only worker allowed to run the whole suite. Run the touched packages' tests with coverage and report the changed lines and branches no test executes. If the suite can't run here, say why and estimate from reading.
3. **Untested flows.** Each requirement, error path, edge case and integration point (callers, other flows on the same data, third parties) with no test.
4. **End-to-end tests to run at the end.** The few end-to-end scenarios worth running before this ships — on a local stack, staging or by hand — each with its steps and the expected result.

## 4. Run the judge

Once every worker has returned, create the report directory outside the worktree, so it survives the cleanup:

```bash
report="${TMPDIR:-/tmp}/code-review-$(git rev-parse --short <head>)-report"
mkdir -p "$report/evidence"
```

Then spawn the judge with every flag, each tagged with its subtask, plus the mission, the design write-up and requirement map from the workers, the context from step 2 including the earlier review threads, and the report directory's path as `<report-dir>`. The workers are done with the worktree, so the judge can run their tests and write its own there; nothing touches the user's checkout.

You are the judge. Workers raised flags with their evidence; most reviews drown the reader in flags nobody needs. Your job is to keep only what is real and worth acting on. A review with no findings is a good result when the change is sound — never promote a weak flag to fill the summary.

1. **Merge** flags that describe the same problem, keeping every worker's evidence.
2. **Check it is real.** Run the worker's test or follow its trace through the actual code. For a bug, ask whether the input or state can reach this code in production, or whether something already catches it — validation upstream, a caller guard, a DB constraint, an earlier check; name the guard. For a missing requirement, check the requirement really is in the mission and really isn't implemented elsewhere. For a reuse flag, read the existing code and, where you can, run it on the same inputs to show it behaves the same. If a flag is real for a different reason than given, keep it with the real reason.
3. **Check it is worth reporting.** Filter out: a flow so unlikely or unreliable that nobody will hit it, a flow nobody cares about, a small improvement that changes nothing for users or maintainers, a nitpick, a preference the repo doesn't document. When in doubt about a missing feature, a data-loss or security bug, keep it.
4. **Check it against earlier review.** Drop a flag a reviewer already raised and the author answered or fixed; it isn't news. Raise one yourself for a review thread marked resolved whose code didn't change and whose reply doesn't explain why — the comment was closed, not addressed.
5. **Rate what's left:**
   - **Blocker** — the mission isn't met (a missing feature, a broken main path), data is lost or corrupted, a security hole, or a production outage on a path real traffic takes.
   - **Should fix** — a real bug on a less common path, a design choice that will cost the next change, a flow with no test where a regression would go unnoticed.
   - **Extra** — everything else that is real but below that bar: a simpler design, a reuse, a clearer name, a minor gap. These go in the file only, never in the summary.

Then write the review in two parts, and give each kept finding an ID (`M1`, `D1`, `Q1`, `B1`, `T1` — by subtask) used in both:

- **Summary**, returned as your answer: a one-line verdict on whether the change fulfils its mission and is ready, then each blocker and should-fix as one short line — ID, rating, `file:line`, and what is wrong in plain words — grouped by subtask in order (mission, design, code quality, bugs, tests), then the end-to-end tests to run. If there are none, say so in one line; don't list extras to fill the space.
- **Full review**, written to `<report-dir>/review.md`. It opens with what was reviewed — the PR or branch, the head commit, the date, which worker shape ran, and whether tests could run — then goes by subtask in the same order, each blocker and should-fix under its ID with its evidence — the failing test and how to run it, the traced path, the quoted requirement — why it matters, and the suggested fix. Include the design as you understand it and the requirement-to-code map. Then **Extras**: each extra, one short paragraph with `file:line` and the suggestion. End with **Ruled out**: one line per filtered flag and why, so the reader sees what was checked. Copy every test or script cited as evidence into `<report-dir>/evidence/`, keeping its path relative to the repo root, and link to it from the finding.

## 5. Report

When the judge returns, open with its summary as it is — one short line per blocker and should-fix, nothing else — and end with the absolute path to `$report/review.md` for the evidence, the full review, and the extras (say how many extras there are, without listing them). Then remove the worktree: `git worktree remove --force "$wt"`. The evidence is already copied out.

## Re-review

When the user asks to review the same PR or branch again, usually after fixing findings:

1. **Find the previous review**: the newest `${TMPDIR:-/tmp}/code-review-*-report/review.md` whose header names the same PR or branch. If there is none, or more than one could fit, ask the user for its path.
2. **Run steps 1–4 on the new head as usual**, and also give every worker the diff since the previously reviewed head (`git -C "$wt" diff <previous head> HEAD`), to read closely: fixes are where new bugs come from.
3. **Give the judge the previous `review.md` too.** For every earlier finding, it records **fixed** (with what fixed it), **still open**, or **no longer applies** (the code was removed or rewritten). It keeps earlier IDs and numbers new findings after the highest earlier one, and doesn't re-raise a flag the earlier review ruled out unless the code under it changed.
4. **The summary opens with the earlier findings' status**, one line each, before the new findings.

## Where not to spend effort

- Anything a linter, formatter or type checker already enforces.
- Style preferences the repo doesn't document.
- Unchanged code, unless the change breaks it or it breaks the change.
