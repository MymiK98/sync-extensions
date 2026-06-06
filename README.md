# sync-extensions

> 📌 **AI로 개인이 사용하는 Claude Code 스킬을 정리·관리하는 개인용 repository입니다.**
> A personal repository for curating and managing one's own Claude Code skills,
> built and maintained with the help of AI.

A personal **skill warehouse** for Claude Code. Two ways to use it:

- **Sync everything** — `bootstrap.sh` / `/sync-extensions` installs the whole
  curated stack at once.
- **Pick & choose (à la carte)** — `use.sh` lists every available skill and lets
  you install or remove them one at a time, including your own skills stored in
  `library/`.

Keeps these installed and up to date:

| Source repo | Asset | Mechanism |
|---|---|---|
| `JuliusBrussee/caveman` | caveman (+ hooks, statusline, level=full) | plugin |
| `obra/superpowers` → `anthropics/claude-plugins-official` | superpowers | plugin |
| `Lum1104/Understand-Anything` | understand-anything | plugin |
| `anthropics/claude-plugins-official` | skill-creator | plugin |
| `forrestchang/andrej-karpathy-skills` | karpathy-guidelines | plugin |
| `bradautomates/claude-video` | watch (claude-video) | plugin |
| `mattpocock/skills` | grill-me, grill-with-docs, handoff, improve-codebase-architecture | standalone (skills CLI) |
| `vercel-labs/skills` | find-skills | standalone (skills CLI) |

## Install on a new machine

```bash
git clone https://github.com/MymiK98/sync-extensions.git
cd sync-extensions
bash bootstrap.sh
```

`bootstrap.sh`:
1. **preflight** — checks `claude`, `node ≥18`, `npx`, `python3`, `git`.
2. **installs the skill** to `~/.claude/skills/sync-extensions`.
3. **seeds standalone skills** — copies the bundled `mattpocock` + `find-skills`
   into `~/.agents/skills` and `.skill-lock.json` so their update runs
   **non-interactively** (no "which skill?" prompts). Existing files are kept,
   never clobbered.
4. **runs a full sync** — adds marketplaces, installs/updates all plugins, runs
   caveman/karpathy basic setup, updates standalone skills.

Then **restart Claude Code**. After that, re-sync anytime with `/sync-extensions`.

### Flags
- `bash bootstrap.sh --no-sync` — install + seed only, skip the sync run.

## Prerequisites
- [Claude Code](https://claude.com/claude-code) (`claude` on PATH)
- Node.js ≥ 18 (provides `npx`)
- Python 3

## What "basic setup" does
- **caveman**: re-runs its idempotent hook installer (SessionStart +
  UserPromptSubmit hooks, statusline badge wired into `settings.json`) and
  ensures `~/.claude/.caveman-active` exists with level `full`. Existing level
  kept.
- **karpathy**: verifies the `karpathy-guidelines` skill is present (auto-loads
  via the plugin system; no mutation).

## Pick & use individual skills (à la carte)

Instead of installing everything, select what you want:

```bash
bash use.sh                  # list the whole catalog (● on / ○ off)
bash use.sh add caveman      # install one
bash use.sh add grill-me handoff   # install several
bash use.sh remove caveman   # remove one
bash use.sh installed        # show only what's currently on
```

The catalog merges three sources automatically:

| Type | Where it comes from | `add` does |
|---|---|---|
| `plugin` | `skill/manifest.json` → `plugins[]` | adds marketplace if needed, `claude plugin install` |
| `standalone` | `manifest.json` → `standalone_skills.repos[]` | `npx skills@latest add <repo>` |
| `local` | `library/<id>/SKILL.md` (your own) | symlinks into `~/.claude/skills` |

Restart Claude Code after installing. Removing a `local`/`standalone` skill only
unlinks it from `~/.claude/skills`; the warehouse copy is never deleted.

## Personal warehouse (`library/`)

Store your own skills in `library/<name>/SKILL.md` — they appear in the catalog
as type `local` and install individually with `use.sh add <name>`. See
[`library/README.md`](library/README.md) and the `example-hello` template.

Author a new one fast with the bundled skill-creator: ask Claude to
"create a skill" (the `skill-creator` plugin), then move the result into
`library/` and `bash publish.sh`.

## Adding a skill / plugin and pushing it to this repo

The **live** copy at `~/.claude/skills/sync-extensions/manifest.json` is what the
sync actually reads. Workflow:

1. **Edit the live manifest** —
   `~/.claude/skills/sync-extensions/manifest.json`:
   - new plugin → add to `marketplaces` (if a new repo) and `plugins`
   - new standalone skill → add to `standalone_skills.repos`
2. **Apply it** — run `/sync-extensions` (installs the new asset locally).
3. **Push it to git** — from the repo, run:
   ```bash
   bash publish.sh "feat: add <name>"
   ```
   `publish.sh` snapshots the live state back into the bundle
   (`skill/` + `agents-seed/`) and pushes. New standalone skills installed into
   `~/.agents` are captured automatically — no manual copying.

On other machines: `git pull`, then re-run `bash bootstrap.sh` (or
`/sync-extensions`) to pick up the new asset.

### publish.sh flags
- `bash publish.sh` — auto commit message + push
- `bash publish.sh "msg"` — custom message + push
- `bash publish.sh --no-push "msg"` — commit only

## Gotchas
- **Marketplace trust prompts**: `claude plugin marketplace add` asks to trust
  each new repo — one-time, ~5 approvals on a fresh machine. Unavoidable via CLI.
- **superpowers** is intentionally sourced from the official marketplace, not
  `obra/superpowers` directly.
- Standalone-skill updates need network + `npx`; offline runs skip that section,
  plugin sync still completes.

## Layout
```
sync-extensions/
├── bootstrap.sh           # fresh-machine installer (repo -> live, installs ALL)
├── use.sh                 # à la carte: list / add / remove individual skills
├── publish.sh             # snapshot live state back into repo + push
├── README.md
├── bin/
│   └── catalog.py         # merged catalog + install-status engine
├── skill/                 # the sync-extensions skill (deployed to ~/.claude/skills)
│   ├── SKILL.md
│   ├── manifest.json      # canonical asset list — edit this
│   └── scripts/sync.sh
├── library/               # YOUR personal skill warehouse (type: local)
│   ├── README.md
│   └── example-hello/SKILL.md
└── agents-seed/           # non-interactive seed for standalone skills
    ├── .skill-lock.json
    └── skills/…
```
