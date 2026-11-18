## Flags

Raise flags, not verdicts. Aim for recall: keep a flag you are unsure of and say so, because the judge decides what is real and worth reporting. Drop a flag you can't give evidence for.

Number each flag with the lowercase letter of the subtask it belongs to — `m1`, `d1`, `q1`, `b1`, `t1`, `p1` — and write each one in exactly this shape:

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
