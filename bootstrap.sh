#!/usr/bin/env bash
# Warehouse bootstrap for a fresh machine.
# Installs ALL skills stored in this repo (skills/*) into ~/.claude/skills, then
# runs each skill's setup. For sync-extensions that means seeding the standalone
# skills non-interactively and running a full sync.
#
# Usage:
#   bash bootstrap.sh             # install all warehouse skills + run setup
#   bash bootstrap.sh --no-sync   # install/link only, skip sync-extensions sync
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SKILLS_DIR="$CLAUDE_DIR/skills"
AGENTS_DIR="$HOME/.agents"
SEEDS="$HERE/seeds/agents"
DO_SYNC=1
[ "${1:-}" = "--no-sync" ] && DO_SYNC=0

say(){ printf '\n\033[1m%s\033[0m\n' "$*"; }
ok(){ printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn(){ printf '  \033[33m!\033[0m %s\n' "$*"; }

detect_os() { # -> linux | macos | windows
  case "${OSTYPE:-$(uname -s 2>/dev/null)}" in
    darwin*|Darwin*) echo macos ;;
    msys*|cygwin*|mingw*|MINGW*|MSYS*|win32) echo windows ;;
    *) echo linux ;;
  esac
}

# safe_link <link> <symlink_target> <copy_source>: symlink, falling back to a
# recursive copy from <copy_source> where symlinks are unsupported (Windows).
safe_link() {
  local link="$1" target="$2" src="$3"
  if ln -s "$target" "$link" 2>/dev/null; then return 0; fi
  warn "symlink unsupported here — copying instead (edits won't auto-track the repo)"
  cp -R "$src" "$link"
}

OS="$(detect_os)"

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

# ---------- 1. link every warehouse skill ----------
say "installing all warehouse skills"
bash "$HERE/install.sh" all

# ---------- 2. sync-extensions setup: seed standalone skills ----------
if [ -d "$SEEDS" ]; then
  say "seeding standalone skills (sync-extensions) -> $AGENTS_DIR"
  mkdir -p "$AGENTS_DIR/skills"
  for d in "$SEEDS"/skills/*/; do
    name="$(basename "$d")"
    if [ -e "$AGENTS_DIR/skills/$name" ]; then ok "$name present (kept)"
    else cp -R "$d" "$AGENTS_DIR/skills/$name"; ok "$name seeded"; fi
  done
  if [ -f "$AGENTS_DIR/.skill-lock.json" ]; then
    warn ".skill-lock.json exists — kept"
  else
    cp "$SEEDS/.skill-lock.json" "$AGENTS_DIR/.skill-lock.json"; ok ".skill-lock.json seeded"
  fi
  # link standalone skills into ~/.claude/skills (copy fallback on Windows)
  for d in "$AGENTS_DIR"/skills/*/; do
    name="$(basename "$d")"; link="$SKILLS_DIR/$name"
    if [ -L "$link" ] || [ -e "$link" ]; then ok "link $name exists"
    else safe_link "$link" "../../.agents/skills/$name" "$AGENTS_DIR/skills/$name"; ok "linked $name"; fi
  done
fi

# ---------- 3. run sync-extensions full sync ----------
if [ "$DO_SYNC" = "1" ] && [ -f "$SKILLS_DIR/sync-extensions/scripts/sync.sh" ]; then
  say "running sync-extensions full sync"
  echo "  NOTE: 'claude plugin marketplace add' may prompt to trust each new repo"
  echo "        (one-time, ~5 approvals on a fresh machine)."
  case "$OS" in
    macos)   echo "  NOTE: on Apple Silicon, ensure Homebrew's bin (/opt/homebrew/bin) and"
             echo "        ~/.local/bin are on PATH so the headroom CLI resolves." ;;
    windows) echo "  NOTE: on Windows, run this under Git Bash or WSL. Symlinks fall back"
             echo "        to copies unless Developer Mode is enabled." ;;
  esac
  bash "$SKILLS_DIR/sync-extensions/scripts/sync.sh"
else
  say "skipped sync (--no-sync or sync-extensions not linked)"
fi

say "done — RESTART Claude Code to load skills."
