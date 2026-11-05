#!/usr/bin/env bash
# Lint marketplaces, plugin manifests, .mcp.json files and SKILL.md frontmatter.
set -euo pipefail
cd "$(dirname "$0")/.."

exec python3 -I - <<'PY'
import json, re, sys
from pathlib import Path

errors = []
def err(msg): errors.append(msg)

def load_json(path):
    try:
        return json.loads(Path(path).read_text())
    except FileNotFoundError:
        err(f"{path}: missing")
    except json.JSONDecodeError as e:
        err(f"{path}: invalid JSON ({e})")
    return None

NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")

claude_mp = load_json(".claude-plugin/marketplace.json") or {}
codex_mp = load_json(".agents/plugins/marketplace.json") or {}

claude_plugins = {p["name"]: p["source"] for p in claude_mp.get("plugins", [])}
codex_plugins = {p["name"]: p["source"]["path"] for p in codex_mp.get("plugins", [])}
plugin_dirs = {p.name for p in Path("plugins").iterdir() if p.is_dir()}

if set(claude_plugins) != set(codex_plugins):
    err(f"marketplaces disagree: claude={sorted(claude_plugins)} codex={sorted(codex_plugins)}")
for name in plugin_dirs - set(claude_plugins) - set(codex_plugins):
    err(f"plugins/{name}: not listed in any marketplace")

for name in sorted(set(claude_plugins) | set(codex_plugins)):
    pdir = Path("plugins") / name
    for src in (claude_plugins.get(name), codex_plugins.get(name)):
        if src and Path(src).resolve() != pdir.resolve():
            err(f"marketplace entry '{name}' points to {src}, expected ./plugins/{name}")
    if not pdir.is_dir():
        err(f"{pdir}: listed in marketplace but missing")
        continue

    cm = load_json(pdir / ".claude-plugin/plugin.json") or {}
    xm = load_json(pdir / ".codex-plugin/plugin.json") or {}
    for label, m in (("claude", cm), ("codex", xm)):
        if m and m.get("name") != name:
            err(f"{pdir}: {label} plugin.json name '{m.get('name')}' != '{name}'")
    if cm and xm and cm.get("version") != xm.get("version"):
        err(f"{pdir}: version mismatch claude={cm.get('version')} codex={xm.get('version')}")

    mcp = pdir / ".mcp.json"
    if mcp.exists():
        data = load_json(mcp)
        if data is not None and not isinstance(data.get("mcpServers"), dict):
            err(f"{mcp}: must contain an 'mcpServers' object")

    for sdir in sorted(p for p in (pdir / "skills").glob("*") if p.is_dir()):
        skill = sdir / "SKILL.md"
        if not skill.exists():
            err(f"{sdir}: missing SKILL.md")
            continue
        text = skill.read_text()
        m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
        if not m:
            err(f"{skill}: missing YAML frontmatter")
            continue
        fm, key = {}, None
        for line in m.group(1).splitlines():
            if line[:1] in (" ", "\t"):          # continuation of a block scalar (>-, |, ...)
                if key:
                    fm[key] = (fm[key] + " " + line.strip()).strip()
                continue
            if ":" not in line:
                continue
            key, _, v = line.partition(":")
            key, v = key.strip(), v.strip()
            fm[key] = "" if v in (">", ">-", ">+", "|", "|-", "|+") else v.strip('"\'')
        sname, desc = fm.get("name", ""), fm.get("description", "")
        if sname != sdir.name:
            err(f"{skill}: name '{sname}' != folder '{sdir.name}'")
        if not NAME_RE.match(sname) or len(sname) > 64:
            err(f"{skill}: invalid name '{sname}'")
        if not desc:
            err(f"{skill}: missing description")
        elif len(desc) > 1024:
            err(f"{skill}: description is {len(desc)} chars (max 1024)")
        elif "TODO" in desc:
            err(f"{skill}: description still has TODO")

if errors:
    print("\n".join(f"✗ {e}" for e in errors))
    sys.exit(1)
skills = sum(1 for _ in Path("plugins").glob("*/skills/*/SKILL.md"))
print(f"✓ {len(plugin_dirs)} plugin(s), {skills} skill(s) OK")
PY
