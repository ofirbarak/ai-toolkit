# ai-toolkit

Shared agent skills, plugins and MCP server configs, usable from any repo with **Claude Code** and **Codex**.
One `SKILL.md` per skill serves both tools.

## Use it

Pick **one** of the two methods below per tool. Doing both makes each skill show up twice.

### A. As a plugin marketplace (versioned, namespaced: `core:my-code-review`)

Claude Code:

```bash
claude plugin marketplace add ~/git/ai-toolkit      # or <github-owner>/ai-toolkit once pushed
claude plugin install core@ai-toolkit
```

Codex:

```bash
codex plugin marketplace add ~/git/ai-toolkit       # or <github-owner>/ai-toolkit once pushed
codex plugin add core@ai-toolkit
```

Plugins can also ship MCP servers via `plugins/<plugin>/.mcp.json`.

### B. As plain skills (symlinked, edits are live, no namespace)

```bash
scripts/install.sh                         # all repos: ~/.claude/skills + ~/.agents/skills
scripts/install.sh --project ~/git/myrepo  # one repo:  myrepo/.claude/skills + myrepo/.agents/skills
scripts/install.sh --project ~/git/myrepo --copy   # vendor copies you can commit into that repo
scripts/install.sh --uninstall             # remove links pointing into this repo
```

Symlinks are best while you're authoring: edit the SKILL.md here and the next session picks it up.

## Write a skill

```bash
scripts/new-skill.sh my-skill        # creates plugins/core/skills/my-skill/SKILL.md
$EDITOR plugins/core/skills/my-skill/SKILL.md
scripts/validate.sh
```

Then try it: in Claude Code type `/my-skill` (or `/core:my-skill` via the plugin); in Codex type `$my-skill`
or describe the task and let the agent pick it from the description.

Authoring rules and repo layout are in [AGENTS.md](AGENTS.md) — that file is what agents working in this repo read.

## Skills

| Plugin | Skill | What it does |
|---|---|---|
| core | [my-code-review](plugins/core/skills/my-code-review/SKILL.md) | Reviews a branch/PR with three finder sub-agents and a judge that tries to disprove each finding with a failing test |
