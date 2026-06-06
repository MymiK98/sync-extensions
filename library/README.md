# library/ — personal skill warehouse

Your own Claude Code skills live here, one folder per skill, each with a
`SKILL.md`. They show up in the catalog as type `local` and can be installed
individually with `use.sh`.

## Add a skill to the warehouse
```
library/
└── my-skill/
    └── SKILL.md        # required (with name: + description: frontmatter)
    └── scripts/ ...    # optional supporting files
```

Then:
```bash
bash ../use.sh list             # see it listed as local / off
bash ../use.sh add my-skill     # symlink it into ~/.claude/skills
bash ../publish.sh "feat: add my-skill"   # push to git
```

`use.sh add <id>` symlinks `library/<id>` into `~/.claude/skills/<id>`, so the
skill loads next Claude Code session. `use.sh remove <id>` unlinks it (the
warehouse copy is never deleted).

See `example-hello/SKILL.md` for a minimal template.
