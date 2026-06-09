# claude-skill-warehouse

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
3. Commit it: `git add -A && git commit -m "feat: add <name>" && git push`
   (only the repo owner has write access).

On another machine: `git pull`, then `bash install.sh add <name>` (or
`bash bootstrap.sh` for everything).

## Fresh machine (install everything)

```bash
git clone https://github.com/MymiK98/claude-skill-warehouse.git
cd claude-skill-warehouse
bash bootstrap.sh
```
`bootstrap.sh`: preflight → link all warehouse skills → seed standalone skills
non-interactively → run the sync-extensions full sync. Then restart Claude Code.
`--no-sync` links only.

## About the `sync-extensions` skill (skill #1)

A one-command sync of a curated Claude Code stack. It keeps these installed and
current (this is the skill's **payload**, managed via its `manifest.json` — not
warehouse entries):

| Source repo | Asset | Mechanism | Priority |
|---|---|---|---|
| `anthropics/claude-plugins-official` | skill-creator | plugin | **base** |
| `forrestchang/andrej-karpathy-skills` | karpathy-guidelines | plugin | **base** |
| `vercel-labs/skills` | find-skills | standalone | **base** |
| `JuliusBrussee/caveman` | caveman (+ hooks, statusline, level=full) | plugin | optional |
| `Lum1104/Understand-Anything` | understand-anything | plugin | optional |
| `mattpocock/skills` | grill-me, grill-with-docs, handoff, improve-codebase-architecture | standalone | optional |
| `bradautomates/claude-video` | watch (claude-video) | plugin | extra |
| `chopratejas/headroom` | headroom (token-compression hooks + CLI) | plugin | extra |

To change the payload, edit `skills/sync-extensions/manifest.json`, run
`/sync-extensions`, then commit with git (owner only).

### Asset priorities (base / optional / extra)
Each asset has a `priority`. **base** always installs (mandatory). **optional**
(default-on) and **extra** (default-off, for heavy/niche assets) install only when
selected. Manage selections — which persist in
`~/.claude/.sync-extensions-selection.json` and survive future syncs:
```bash
bash skills/sync-extensions/scripts/sync.sh --check               # show groups + current selection
bash skills/sync-extensions/scripts/sync.sh --enable watch,headroom  # turn extras on (persists)
bash skills/sync-extensions/scripts/sync.sh --disable caveman        # turn an optional off (persists)
bash skills/sync-extensions/scripts/sync.sh --all                  # include everything this run
bash skills/sync-extensions/scripts/sync.sh --base-only            # base assets only this run
```
A run ends with a **verification summary** (per-asset action/state + warnings) and
exits non-zero only if a base asset fails.

### Basic setup the sync performs
- **caveman**: idempotent hook installer (SessionStart + UserPromptSubmit hooks,
  statusline badge in `settings.json`) + ensures `~/.claude/.caveman-active=full`.
- **karpathy**: verifies the `karpathy-guidelines` skill is present (auto-loads).
- **headroom**: ensures the `headroom` CLI is installed (`pip install
  "headroom-ai[all]"`) and symlinked onto PATH (`~/.local/bin`), so the plugin's
  SessionStart/PreToolUse hook (`headroom init hook ensure`) auto-initializes the
  runtime each session.

## Prerequisites
- [Claude Code](https://claude.com/claude-code) (`claude` on PATH)
- Node.js ≥ 18 (provides `npx`) · Python 3 · git

## Cross-platform
Works on **Linux**, **macOS** (including Apple Silicon / M1 — the sync searches
`/opt/homebrew/bin` and npm-global dirs for the `headroom` CLI), and **Windows**
via **Git Bash or WSL**. Where symlinks aren't permitted (Windows without
Developer Mode), `install.sh`/`bootstrap.sh` fall back to copying the skill
folder. `.gitattributes` enforces LF endings so scripts don't break on Windows
checkout, and all scripts honor `CLAUDE_CONFIG_DIR` and tolerate paths with spaces.

## Layout
```
claude-skill-warehouse/
├── README.md
├── bootstrap.sh        # fresh machine: install all warehouse skills + setup
├── install.sh          # pick & install/remove individual stored skills
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
  each new repo — one-time, ~6 approvals on a fresh machine.
- **headroom** pulls a large Python dependency tree (torch, transformers, …) on
  first install; budget a few minutes. Needs `~/.local/bin` on PATH.
- Standalone-skill updates need network + `npx`.
