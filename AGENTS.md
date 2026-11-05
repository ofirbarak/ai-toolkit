# AGENTS.md

Instructions for AI agents (Claude Code, Codex, others) working **in this repo**.

## What this repo is

A shared library of agent skills, plugins, and MCP server configs that other repos consume.
The repo is simultaneously:

- a **Claude Code plugin marketplace** — `.claude-plugin/marketplace.json`
- a **Codex plugin marketplace** — `.agents/plugins/marketplace.json`
- a **plain skills folder** that `scripts/install.sh` symlinks into `~/.claude/skills` and `~/.agents/skills` (or into a single project)

Everything lives in one source tree; there is no build step.

## Layout

```
.claude-plugin/marketplace.json   Claude marketplace: lists plugins under plugins/
.agents/plugins/marketplace.json  Codex marketplace: same plugins, Codex schema
plugins/<plugin>/
  .claude-plugin/plugin.json      Claude plugin manifest
  .codex-plugin/plugin.json       Codex plugin manifest
  skills/<skill>/SKILL.md         one folder per skill (+ optional scripts/, references/, assets/)
  .mcp.json                       optional: MCP servers this plugin ships (both tools read it)
templates/skill/SKILL.md          starting point for new skills
scripts/new-skill.sh              scaffold a skill from the template
scripts/install.sh                symlink skills into Claude/Codex skill dirs
scripts/validate.sh               lint manifests and SKILL.md frontmatter — run before committing
```

## Adding a skill

1. `scripts/new-skill.sh <skill-name> [plugin]` (plugin defaults to `core`).
2. Edit `plugins/<plugin>/skills/<skill-name>/SKILL.md`.
3. `scripts/validate.sh`.

SKILL.md rules (the open Agent Skills format — both Claude and Codex read it):

- YAML frontmatter with exactly `name` and `description` (others are optional and tool-specific).
- `name`: lowercase, digits, hyphens; must equal the folder name; ≤ 64 chars.
- `description`: ≤ 1024 chars, third person, says **what it does and when to use it**. This is the only
  text the agent sees before deciding to load the skill, so put the trigger phrases here.
- Body: imperative instructions for the agent, not docs for humans. Keep it under ~500 lines;
  move long reference material into `references/*.md` and link to it from the body.
- Scripts go in `scripts/` inside the skill and are referenced by relative path.
- No tool-specific syntax (no Claude-only tool names, no Codex-only commands) unless the skill is
  deliberately single-tool — then say so in the description.

## Adding a plugin

1. Copy `plugins/core` to `plugins/<name>`, empty its `skills/`, update both `plugin.json` files.
2. Add an entry to **both** marketplace files.
3. `scripts/validate.sh`.

## Adding an MCP server

Put it in the owning plugin's `.mcp.json`:

```json
{
  "mcpServers": {
    "my-server": { "command": "npx", "args": ["-y", "some-mcp-server"], "env": { "API_KEY": "${API_KEY}" } }
  }
}
```

Never commit secrets — reference env vars only.

## Conventions

- Bump `version` in both `plugin.json` files when a plugin's contents change (Claude caches by version).
- Keep the two marketplace files and the two manifests per plugin in sync; `validate.sh` checks this.
- Don't add per-tool copies of a skill. One SKILL.md serves both tools.
