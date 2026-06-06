---
name: example-skill
description: Minimal template skill for the personal warehouse. Copy this folder into skills/<name>/, rename it, and replace this description with what your skill actually does so the catalog and Claude's skill picker show something useful.
---

# example-skill

Template for a warehouse skill. Copy this folder into `skills/<name>/`, rename
it, and edit `SKILL.md`.

## What a skill needs
- `name:` — kebab-case, must match the folder name.
- `description:` — one line; this is what Claude reads to decide when to use the
  skill, and what `install.sh list` shows. Make it specific and trigger-rich.

## Body
Put the actual instructions here — the steps Claude should follow when the skill
is invoked. Reference supporting files with paths relative to this folder, e.g.
`scripts/do-thing.sh`.

To store and use this skill:
```bash
bash install.sh add <name>          # link into ~/.claude/skills
bash publish.sh "feat: add <name>"  # push to git
```
