#!/usr/bin/env python3
"""Fills this skill's prompt templates with the slot files a review has written so far.

Usage: assemble.py <report-dir> <template> [<template> ...]

Reads every <report-dir>/slots/<name>.md as slot `name`, expands each template from
prompts/<template>.md, and writes the result to <report-dir>/prompts/<template>.md.
A template with an unfilled slot is not written, and the exit status is 1, so a step
can't start on a half-built prompt.
"""

import re
import sys
from pathlib import Path

PROMPTS = Path(__file__).resolve().parent / "prompts"
INCLUDE = re.compile(r"\{\{include:([\w.-]+)\}\}")
SLOT = re.compile(r"\{\{(\w+)\}\}")


def load_slots(report: Path) -> dict[str, str]:
    slots = {path.stem: path.read_text().strip() for path in (report / "slots").glob("*.md")}
    slots["report_dir"] = str(report)
    return slots


def assemble(template: str, slots: dict[str, str]) -> tuple[str, list[str]]:
    text = (PROMPTS / f"{template}.md").read_text()
    text = INCLUDE.sub(lambda match: (PROMPTS / match.group(1)).read_text(), text)
    missing = sorted(set(SLOT.findall(text)) - slots.keys())
    return SLOT.sub(lambda match: slots.get(match.group(1), match.group(0)), text), missing


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    report = Path(sys.argv[1]).resolve()
    slots = load_slots(report)
    out = report / "prompts"
    out.mkdir(exist_ok=True)
    status = 0
    for template in sys.argv[2:]:
        prompt, missing = assemble(template, slots)
        if missing:
            print(f"{template}: missing slots {', '.join(missing)}", file=sys.stderr)
            status = 1
            continue
        (out / f"{template}.md").write_text(prompt)
        print(out / f"{template}.md")
    return status


if __name__ == "__main__":
    sys.exit(main())
