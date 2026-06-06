---
name: example-hello
description: Minimal template skill for the personal warehouse. Use as a starting point when authoring a new local skill; replace this description with what your skill actually does so the catalog and Claude's skill picker show something useful.
---

# example-hello

Template for a personal warehouse skill. Copy this folder, rename it, and edit
`SKILL.md`.

## What a skill needs
- `name:` — kebab-case, must match the folder name.
- `description:` — one line; this is what Claude reads to decide when to use the
  skill, and what `use.sh list` shows. Make it specific and trigger-rich.

## Body
Put the actual instructions here — the steps Claude should follow when the skill
is invoked. Reference supporting files with paths relative to this folder, e.g.
`scripts/do-thing.sh`.

Delete this template once you have real skills in `library/`.
