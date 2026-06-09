---
name: sync-extensions
description: Install, set up, and update (최신화) the user's curated set of Claude Code plugins and standalone skills — caveman, superpowers, understand-anything, skill-creator, karpathy-guidelines, claude-video/watch, and the mattpocock skills (grill-me, grill-with-docs, handoff, improve-codebase-architecture). Use when the user wants to sync, install, refresh, update, or 최신화 their Claude plugins/skills/MCP stack, or asks to "sync extensions".
---

# sync-extensions

Keeps the user's curated Claude Code stack installed and current from a single
manifest. Two install mechanisms are handled:

1. **Marketplace plugins** — via `claude plugin` CLI (caveman, superpowers,
   understand-anything, skill-creator, andrej-karpathy-skills, watch/claude-video).
2. **Standalone skills** — via the vercel `skills` CLI, tracked in
   `~/.agents/.skill-lock.json` (grill-me, grill-with-docs, handoff,
   improve-codebase-architecture, find-skills).

The canonical list lives in `manifest.json` (next to this file). Edit it to
add/remove items.

## Asset priorities (base / optional / extra)

Every asset in `manifest.json` carries a `priority`:

- **base** — mandatory, **always** installed regardless of selection.
- **optional** — installed when selected; `default: true` ⇒ on until the user
  deselects it.
- **extra** — installed when selected; `default: false` ⇒ off until the user
  enables it (use for heavy/niche assets, e.g. headroom's torch/transformers).

User choices persist in `$CLAUDE_CONFIG_DIR/.sync-extensions-selection.json`
(default `~/.claude/...`). They override the manifest `default` and survive
future syncs. Manage them with `--enable`/`--disable` (see below); base is never
affected.

## How to run

Recommended flow: **report → ask the user → enable/disable → dry-run → full sync.**

```bash
# 1. state + priority groups + current selection (no changes made)
bash "$CLAUDE_PLUGIN_ROOT/scripts/sync.sh" --check        # alias: --list

# 2. record the user's optional/extra choices (persists, then continues)
bash "$CLAUDE_PLUGIN_ROOT/scripts/sync.sh" --enable watch,headroom --disable caveman
#    or include everything this run:   --all
#    or base assets only this run:     --base-only

# 3. preview the resulting plan — prints every command, executes nothing
bash "$CLAUDE_PLUGIN_ROOT/scripts/sync.sh" --dry-run

# 4. full sync — add missing marketplaces, install selected plugins, update all
bash "$CLAUDE_PLUGIN_ROOT/scripts/sync.sh"
```

After `--check`, **ask the user which optional/extra assets they want**, then run
`--enable a,b --disable c` before the full sync. Base assets always install.

If `$CLAUDE_PLUGIN_ROOT` is unset (skill loaded as `sync-extensions@skills-dir`),
use the absolute path instead:
`bash ~/.claude/skills/sync-extensions/scripts/sync.sh`

## What the script does

- **Marketplaces**: adds any listed marketplace not in
  `~/.claude/plugins/known_marketplaces.json`, then `marketplace update` to
  refresh metadata.
- **Plugins**: for each manifest plugin that is *included* by its priority +
  selection, `install <name>@<marketplace>` if absent (checked against
  `installed_plugins.json`), else `update <name>`. Deselected optional/extra
  plugins are reported as `[skipped:<priority>]` and their basic-setup is skipped.
- **Basic setup (caveman, karpathy)** — runs after install/update:
  - **caveman**: re-runs `src/hooks/install.sh` (idempotent — wires SessionStart +
    UserPromptSubmit hooks and statusline badge into `settings.json`, skips if
    already present) and ensures `~/.claude/.caveman-active` exists with default
    level `full`. Existing level is kept, not overwritten.
  - **karpathy**: verifies the `karpathy-guidelines` skill dir exists in the
    install path (the plugin auto-loads it; no mutation needed).
- **Standalone skills**: adds each *included* repo not yet in the lock, then runs
  `npx skills@latest update` to refresh tracked ones. Deselected repos are skipped
  (already-installed ones are kept — remove manually if desired).
- **Report**: prints installed plugin versions, then a **verification summary** —
  a per-asset table (priority · action · state) plus collected warnings. The
  script exits non-zero only if a **base** asset fails; optional/extra failures
  (e.g. offline) are tolerated.

## After running

- **Restart Claude Code** — plugin install/update changes apply next session.
- Summarize for the user as a table: each item, action taken (added / installed /
  updated / already-current), and version.
- The script is idempotent — already-current items are simply re-updated, no harm.

## Notes / gotchas

- `claude plugin marketplace add` may prompt to trust a new repo; if a marketplace
  is already in `known_marketplaces.json` the script skips it (no prompt).
- superpowers is intentionally sourced from the official
  `claude-plugins-official` marketplace, not `obra/superpowers` directly.
- Standalone-skill updates need network + `npx`; offline runs (or missing Node)
  skip that section with a warning — plugin sync still completes.
- **Cross-platform**: runs on Linux, macOS (incl. Apple Silicon — searches
  `/opt/homebrew/bin` and npm-global for the `headroom` CLI), and Windows via Git
  Bash/WSL. Honors `CLAUDE_CONFIG_DIR`; tolerates paths containing spaces.
- To add a new plugin: append to `manifest.json` `marketplaces` (if new repo) and
  `plugins` (with a `priority`). To add a standalone skill: append to
  `standalone_skills.repos` (give it a `name` + `priority`).
