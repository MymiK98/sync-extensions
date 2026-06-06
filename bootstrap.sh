#!/usr/bin/env bash
# sync-extensions — bootstrap installer for a fresh machine.
#
# Installs the sync-extensions skill into ~/.claude/skills, seeds the standalone
# skills (mattpocock + find-skills) into ~/.agents so their update runs
# non-interactively, then runs a full sync (marketplaces, plugins, caveman/karpathy
# basic setup, standalone skills).
#
# Usage:
#   bash bootstrap.sh             # install + seed + full sync
#   bash bootstrap.sh --no-sync   # install + seed only, skip the sync run
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SKILLS_DIR="$CLAUDE_DIR/skills"
AGENTS_DIR="$HOME/.agents"
DO_SYNC=1
[ "${1:-}" = "--no-sync" ] && DO_SYNC=0

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()  { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn(){ printf '  \033[33m!\033[0m %s\n' "$*"; }

# ---------- preflight ----------
say "preflight"
MISS=0
for bin in claude node npx python3 git; do
  if command -v "$bin" >/dev/null 2>&1; then ok "$bin"; else warn "$bin MISSING"; MISS=1; fi
done
if command -v node >/dev/null 2>&1; then
  NM=$(node -p "process.versions.node.split('.')[0]")
  [ "$NM" -ge 18 ] && ok "node $NM (>=18)" || { warn "node $NM too old (need >=18)"; MISS=1; }
fi
[ "$MISS" = "1" ] && { echo; echo "Install missing prerequisites and re-run."; exit 1; }

# ---------- 1. install the skill ----------
say "installing skill -> $SKILLS_DIR/sync-extensions"
mkdir -p "$SKILLS_DIR"
rm -rf "$SKILLS_DIR/sync-extensions"
cp -R "$HERE/skill" "$SKILLS_DIR/sync-extensions"
chmod +x "$SKILLS_DIR/sync-extensions/scripts/sync.sh"
ok "skill files copied"

# ---------- 2. seed standalone skills (non-interactive) ----------
say "seeding standalone skills -> $AGENTS_DIR"
mkdir -p "$AGENTS_DIR/skills"
for d in "$HERE"/agents-seed/skills/*/; do
  name="$(basename "$d")"
  if [ -e "$AGENTS_DIR/skills/$name" ]; then
    ok "$name already present (kept)"
  else
    cp -R "$d" "$AGENTS_DIR/skills/$name"
    ok "$name seeded"
  fi
done
# lock: only place ours if target has none (never clobber an existing lock)
if [ -f "$AGENTS_DIR/.skill-lock.json" ]; then
  warn ".skill-lock.json exists — kept (run 'npx skills@latest update' to refresh)"
else
  cp "$HERE/agents-seed/.skill-lock.json" "$AGENTS_DIR/.skill-lock.json"
  ok ".skill-lock.json seeded"
fi
# symlink standalone skills into ~/.claude/skills so Claude Code loads them
for d in "$AGENTS_DIR"/skills/*/; do
  name="$(basename "$d")"
  link="$SKILLS_DIR/$name"
  if [ -L "$link" ] || [ -e "$link" ]; then
    ok "link $name exists"
  else
    ln -s "../../.agents/skills/$name" "$link"
    ok "linked $name"
  fi
done

# ---------- 3. full sync ----------
if [ "$DO_SYNC" = "1" ]; then
  say "running full sync"
  echo "  NOTE: 'claude plugin marketplace add' may prompt to trust each new repo"
  echo "        (one-time, ~5 approvals on a fresh machine)."
  bash "$SKILLS_DIR/sync-extensions/scripts/sync.sh"
else
  say "skipped sync (--no-sync). Run later:"
  echo "  bash $SKILLS_DIR/sync-extensions/scripts/sync.sh"
fi

say "done — RESTART Claude Code to load plugins/skills."
