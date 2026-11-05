---
name: my-code-review
description: >-
  Review changed code with four sub-agents: three finders that hunt inside the
  change, for code it re-implements instead of reusing (repo code, installed
  libraries, common packages), and around it and on its failure paths (callers,
  stacked PRs, interfering flows, third parties, error handling, logging,
  tracing, monitoring), and a judge that tries to disprove every finding with a
  failing test before it is reported. Use when the user wants to review a
  branch, a PR, or work-in-progress changes.
---

Three finders look for problems, each in a different place, and a judge tries to disprove everything they find. The finders aim for recall, the judge for precision. Keeping them apart stops a reviewer from talking itself into its own findings.

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

The diff to review is `git -C "$wt" diff <merge-base> HEAD`. Uncommitted changes are not in the worktree; if the user wants work in progress reviewed, say so and have them commit it first.

## 2. Gather the context

Before spawning anything, collect:

- The diff and the commits (`git -C "$wt" log --oneline <merge-base>..HEAD`), and the PR description and discussion if there is a PR.
- **The stack.** Whether this PR is one of a stack: its base isn't the default branch, or other PRs build on it (`gh pr list --base <headRefName>`). Note each related PR and what it changes.
- The repo's standards files that cover the touched files: `CLAUDE.md` files from the root down to each touched directory, `CONTRIBUTING.md` and the like.

Each sub-agent knows only its prompt, so paste in: the worktree path, with the rule to read code only from there and run every `git` command as `git -C <worktree>`; the diff command, the commits, the PR description, the stack, the finder's or judge's brief below, and **Where not to spend effort**. Finders and the judge are fresh `general-purpose` agents.

## 3. Run the three finders

Spawn all three in one message; they look at different things and don't need each other.

Finders A and C end their briefs with the same rules (Finder B reports in its own format):

> Report candidates, not verdicts. For each: `file:line`, the scenario that triggers it (the exact input, state, or sequence of events), and what goes wrong. Keep a candidate you're unsure can happen in production — a judge decides that. Drop one you can't give a scenario for. Don't edit files.

### Finder A — inside the change

> Read the diff, then enough surrounding code to understand each change. Look for:
>
> 1. **The core change doesn't do what it means to.** Work out the intent from the code, commits, and PR description, then trace the main path through the new code.
> 2. **Edge cases.** Empty, null/None, zero, very large, duplicate, unicode, first-run and retry inputs. Wrong condition, inverted check, off-by-one, a missed case in a branch or match.
> 3. **State and data.** A partial write with no rollback, a cache or derived value left stale, a migration or format change that breaks existing data.
> 4. **Security.** Unvalidated input reaching a query, shell, path, template or redirect; a missing auth or ownership check; a secret returned to a caller.
> 5. **Resources.** Leaks, unbounded loops or growth, N+1 queries, blocking calls on a hot path.
> 6. **Tests.** Changed behaviour with no test covering it, or a test that would still pass if the change were wrong.

### Finder B — reuse instead of re-implementing

> For every piece of the change — each new function, class, helper, constant, type, query, component, script, or config block — work out what it is trying to do, then search for whether that already exists:
>
> 1. **In this repo.** A helper, util, base class, hook, component, query builder, fixture, or config that does the same or nearly the same thing. Search by what the code does, not only by its name; the existing one is often named differently. Also look for the reverse: the change copies a block of existing code instead of calling it or extracting it.
> 2. **In what the repo already depends on.** The language's standard library, the framework, and the packages already installed (check the manifests and lockfiles).
> 3. **In a common, maintained library the repo doesn't use yet**, when the hand-rolled version is non-trivial: parsing, retries and backoff, date and time math, crypto, validation, concurrency, rate limiting.
>
> Then judge whether reusing it is reasonable here. Same behaviour, including edge cases and errors? Would using it be simpler than what was written? For a new library, is the dependency worth it? A near-match that would have to be bent to fit is not a finding.
>
> For each candidate: the new code (`file:line`) and what it does, the existing thing (`path:line`, or package and function), and why it fits. Don't edit files.

### Finder C — around the change, and when it fails

> The change doesn't run alone, and it won't always succeed. First, look outside the diff for:
>
> 1. **Callers.** A changed signature, return shape, default, or API response that unchanged code still relies on. Search for every caller; the diff won't show them.
> 2. **The stack.** What this PR depends on from the PRs below it, and what the PRs above it expect from it. A change that is fine alone but breaks with its stack.
> 3. **Flows that don't touch this code but interfere with it.** Other writers to the same tables or files, background jobs and workers, scheduled tasks, retries, concurrent requests, caches. Find them by searching for the tables, keys, queues and files the change reads or writes.
> 4. **Third parties.** The database (constraints, triggers, locks, isolation level), queues, external APIs, and anything else whose behaviour the change assumes. Check the assumption against how it actually behaves.
>
> Then walk every way the changed code can fail — a thrown error, a timeout, a bad response from one of those callers, flows or third parties, a rejected write — and follow what happens next. When this code fails in production, will anyone know, and can they find out why?
>
> 5. **Failures are loud.** No error swallowed, caught too broadly, logged and ignored, or turned into a misleading default; no fallback that hides a real failure. A failure stops the operation rather than leaving it half done or in a bad state.
> 6. **Errors are understandable.** Error messages and logs say what failed, on which entity, and why, with the IDs needed to look it up.
> 7. **The flow can be tracked.** Logs carry the request or job ID, traces propagate across services and async hops, and a failure shows up in a metric or alert someone watches.
> 8. **It can be debugged.** Someone holding only the logs, traces and metrics could tell which step failed and reproduce it.
> 9. **Nothing leaks.** Logs, errors and traces don't carry secrets or personal data.

## 4. Check standards and smells yourself

This pass needs the standards files, not proof, so it doesn't need a sub-agent. Read the standards files from step 2 in the worktree, and check the diff against them, citing the file and quoting each rule it breaks. Then look for the smells below. Smells are always judgement calls, and a documented standard overrides them.

- **Mysterious Name**: a name that doesn't reveal what it does or holds. → rename; if no honest name comes, the design's murky.
- **Duplicated Code**: the same logic shape in more than one place in the change. → extract it, call it from both.
- **Feature Envy**: a method that reaches into another object's data more than its own. → move it onto that data.
- **Data Clumps**: the same few fields or params travelling together. → bundle them into one type.
- **Primitive Obsession**: a primitive or string standing in for a concept that deserves its own type. → give it one.
- **Repeated Switches**: the same `switch`/`if`-cascade on the same type in several places. → polymorphism, or one shared map.
- **Shotgun Surgery**: one logical change scattered across many files. → gather what changes together.
- **Divergent Change**: one module edited for several unrelated reasons. → split it.
- **Speculative Generality**: abstraction, parameters, or hooks for needs nobody has yet. → delete it.
- **Message Chains**: long `a.b().c().d()` navigation. → hide the walk behind one method.
- **Middle Man**: a class or function that mostly delegates onward. → call the real target.
- **Refused Bequest**: a subclass that ignores most of what it inherits. → use composition.

## 5. Run the judge

Once all three finders have returned, spawn the judge with every candidate from them, plus the context from step 2. The finders are done with the worktree, so the judge writes and runs its tests there; nothing it writes touches the user's checkout.

> You get a list of candidate findings. Assume each is wrong until you prove it. For each:
>
> 1. **Reproduce it.** Write a test that fails on the current code and run it. If a test isn't possible (the bug needs production infrastructure, timing, or a third party you can't stand up), trace the path step by step through the actual code instead, and say why there's no test.
> 2. **Judge whether it can happen.** Can this input or state actually reach this code in production? Is it already caught before it gets here — validation upstream, a caller guard, a DB constraint, an earlier check? Name the guard if you find one.
> 3. **Give a verdict:** **Confirmed** (with the failing test or the traced path, and a severity), **Unreachable**, **Already caught** (name what catches it), or **Not a bug** (say why). If the candidate is real but not for the reason given, confirm the real reason.
>
> Reuse candidates (code that re-implements something that already exists) have no bug to reproduce. Check the fit instead: read the existing code or library function, and where you can, run it on the same inputs as the new code, edge cases included, to show it behaves the same. Verdict: **Confirmed** (it fits, and swapping it in is simpler) or **Doesn't fit** (name the difference that matters).
>
> Return the confirmed findings with their tests, and one line per rejected candidate.

## 6. Report

1. **Confirmed bugs**, most severe first. For each: `file:line`, the scenario, the proof (the failing test, or the traced path), and why it can happen in production.
2. **Reuse**: each piece of new code that should call something existing instead, naming the new code, the existing thing, and how the judge showed it fits.
3. **Standards and smells** from step 4, marked hard (a documented rule) or judgement (a smell).
4. **Ruled out**: one line per rejected candidate and why, so the reader sees what was checked.

Then remove the worktree: `git worktree remove --force "$wt"`. The judge's tests are already in the report.

## Where not to spend effort

- Anything a linter, formatter or type checker already enforces.
- Style preferences the repo doesn't document.
- Unchanged code, unless the change breaks it or it breaks the change.
