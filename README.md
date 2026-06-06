# sync-extensions

> 📌 **AI로 개인이 사용하는 Claude Code 스킬을 정리·관리하는 개인용 repository입니다.**
> A personal repository for storing and managing the Claude Code skills I build,
> with the help of AI.

This repo is my **skill warehouse**. Every skill I make lives under `skills/`,
one folder per skill. The first one is **`sync-extensions`** — a full-sync skill
that installs/updates my whole curated plugin + skill stack. Future skills get
added here too, then pushed to git.

```
skills/
└── sync-extensions/        # skill #1 — the full-sync skill
    ├── SKILL.md
    ├── manifest.json
    └── scripts/sync.sh
# (future) skills/<my-next-skill>/SKILL.md ...
```

## Use stored skills (pick & choose)

`install.sh` lists the warehouse and installs the skills you pick by symlinking
`skills/<id>` into `~/.claude/skills/<id>`.

```bash
bash install.sh                  # list warehouse (● installed / ○ not)
bash install.sh add sync-extensions   # install one
bash install.sh add foo bar      # install several
bash install.sh remove foo       # uninstall (unlink; warehouse copy kept)
bash install.sh all              # install every stored skill
```

Restart Claude Code after installing. For `sync-extensions`, after installing the
skill run `/sync-extensions` (or `bash bootstrap.sh`) to install its payload
(the external plugins + standalone skills it manages).

## Add a NEW skill to the warehouse

1. Create `skills/<name>/SKILL.md` (with `name:` + `description:` frontmatter).
   - Author one fast with the bundled **skill-creator** plugin, then move the
     result into `skills/`. See `templates/example-skill/` for a minimal layout.
2. `bash install.sh add <name>` — link it into `~/.claude/skills` to use it.
3. `bash publish.sh "feat: add <name>"` — commit + push to git.

On another machine: `git pull`, then `bash install.sh add <name>` (or
`bash bootstrap.sh` for everything).

## Fresh machine (install everything)

```bash
git clone https://github.com/MymiK98/sync-extensions.git
cd sync-extensions
bash bootstrap.sh
```
`bootstrap.sh`: preflight → link all warehouse skills → seed standalone skills
non-interactively → run the sync-extensions full sync. Then restart Claude Code.
`--no-sync` links only.

## About the `sync-extensions` skill (skill #1)

A one-command sync of a curated Claude Code stack. It keeps these installed and
current (this is the skill's **payload**, managed via its `manifest.json` — not
warehouse entries):

| Source repo | Asset | Mechanism |
|---|---|---|
| `JuliusBrussee/caveman` | caveman (+ hooks, statusline, level=full) | plugin |
| `anthropics/claude-plugins-official` | superpowers, skill-creator | plugin |
| `Lum1104/Understand-Anything` | understand-anything | plugin |
| `forrestchang/andrej-karpathy-skills` | karpathy-guidelines | plugin |
| `bradautomates/claude-video` | watch (claude-video) | plugin |
| `mattpocock/skills` | grill-me, grill-with-docs, handoff, improve-codebase-architecture | standalone |
| `vercel-labs/skills` | find-skills | standalone |

To change the payload, edit `skills/sync-extensions/manifest.json`, run
`/sync-extensions`, then `bash publish.sh`.

### Basic setup the sync performs
- **caveman**: idempotent hook installer (SessionStart + UserPromptSubmit hooks,
  statusline badge in `settings.json`) + ensures `~/.claude/.caveman-active=full`.
- **karpathy**: verifies the `karpathy-guidelines` skill is present (auto-loads).

## Prerequisites
- [Claude Code](https://claude.com/claude-code) (`claude` on PATH)
- Node.js ≥ 18 (provides `npx`) · Python 3 · git

## Layout
```
sync-extensions/
├── README.md
├── bootstrap.sh        # fresh machine: install all warehouse skills + setup
├── install.sh          # pick & install/remove individual stored skills
├── publish.sh          # refresh seeds from live + commit + push
├── bin/catalog.py      # warehouse catalog + install-status engine
├── skills/             # ← MY skills (the warehouse)
│   └── sync-extensions/{SKILL.md,manifest.json,scripts/sync.sh}
├── seeds/agents/       # standalone-skill seed for sync-extensions (non-interactive)
│   ├── .skill-lock.json
│   └── skills/…
└── templates/
    └── example-skill/SKILL.md   # template for new warehouse skills
```

## Gotchas
- **Marketplace trust prompts**: `claude plugin marketplace add` asks to trust
  each new repo — one-time, ~5 approvals on a fresh machine.
- **superpowers** is sourced from the official marketplace, not `obra/superpowers`.
- Standalone-skill updates need network + `npx`.
