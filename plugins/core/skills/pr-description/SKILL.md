---
name: pr-description
description: Writes a pull request title and description from the current branch's changes. Use when the user asks to write, draft, or update a PR description, PR body, or merge request summary, or right before opening a PR.
---

# PR description

## Steps

1. Find the base branch: use the one the user named; otherwise the PR's base if a PR exists
   (`gh pr view --json baseRefName -q .baseRefName`); otherwise the remote default branch
   (`git symbolic-ref --short refs/remotes/origin/HEAD`, stripping `origin/`).
2. Collect the change set against the merge base:
   - `git log --oneline <base>..HEAD`
   - `git diff --stat <base>...HEAD`
   - `git diff <base>...HEAD` — read it; for very large diffs, read the stat first and then the files that matter.
3. Work out **why** the change exists, not just what lines moved. Use commit messages, linked issue
   IDs in the branch name or commits, and the code itself. If the motivation is not discoverable, ask
   one short question rather than inventing one.
4. Write the description using the template below. Omit any section that would be empty.

## Template

```markdown
<Title: imperative, ≤ 72 chars, no trailing period>

## Why
<1–3 sentences: the problem or goal.>

## What changed
- <Grouped by behavior, not by file. Lead with the user-visible or API-visible change.>

## How to test
- <Commands or manual steps a reviewer can run.>

## Risks / follow-ups
- <Migrations, flags, backwards-compat concerns, known gaps.>
```

## Output

- Print the title and body in chat so the user can review them.
- Only run `gh pr create` / `gh pr edit` if the user asked you to open or update the PR.

## Don't

- Don't list every file touched — reviewers have the diff.
- Don't claim tests pass unless you ran them in this session.
- Don't pad with generic filler ("This PR improves code quality").
