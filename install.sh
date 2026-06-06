#!/usr/bin/env bash
# Warehouse installer — pick which of MY stored skills to use.
# Installs a skill by symlinking skills/<id> into ~/.claude/skills/<id>.
#
# Usage:
#   bash install.sh                 # list warehouse (alias: list)
#   bash install.sh add <id> [...]  # install selected skills
#   bash install.sh remove <id> ... # uninstall (unlink) selected skills
#   bash install.sh all             # install every warehouse skill
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAT="$HERE/bin/catalog.py"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SKILLS_DIR="$CLAUDE_DIR/skills"
PY=python3

command -v "$PY" >/dev/null || { echo "python3 required"; exit 1; }
ok(){ printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn(){ printf '  \033[33m!\033[0m %s\n' "$*"; }

add_one() {
  local id="$1" spec
  spec="$("$PY" "$CAT" get "$id")" || { warn "unknown skill: $id (see: install.sh list)"; return 1; }
  eval "$spec"
  mkdir -p "$SKILLS_DIR"
  local link="$SKILLS_DIR/$id" target="$HERE/$SKILLPATH"
  if [ -L "$link" ]; then ok "$id already linked"
  elif [ -e "$link" ]; then warn "$link exists and is not a symlink — left in place"; return 1
  else ln -s "$target" "$link" && ok "installed $id -> $link"; fi
  # per-skill setup hint
  if [ "$id" = "sync-extensions" ]; then
    echo "      → run '/sync-extensions' (or bash bootstrap.sh) to install its payload"
  fi
}

remove_one() {
  local id="$1" link="$SKILLS_DIR/$1"
  if [ -L "$link" ]; then rm "$link" && ok "uninstalled $id (warehouse copy kept)"
  elif [ -e "$link" ]; then warn "$link is not a symlink — left in place"
  else ok "$id not installed"; fi
}

cmd="${1:-list}"; shift 2>/dev/null || true
case "$cmd" in
  list|"")   "$PY" "$CAT" list ;;
  json)      "$PY" "$CAT" json ;;
  add)       [ "$#" -gt 0 ] || { echo "usage: install.sh add <id> [...]"; exit 2; }
             for id in "$@"; do add_one "$id"; done
             echo; echo "Restart Claude Code to load installed skills." ;;
  all)       for id in $("$PY" "$CAT" json | "$PY" -c "import json,sys;[print(i['id']) for i in json.load(sys.stdin)]"); do add_one "$id"; done
             echo; echo "Restart Claude Code to load installed skills." ;;
  remove|rm) [ "$#" -gt 0 ] || { echo "usage: install.sh remove <id> [...]"; exit 2; }
             for id in "$@"; do remove_one "$id"; done ;;
  *) echo "unknown command: $cmd"; echo "use: list | add <id> | remove <id> | all"; exit 2 ;;
esac
