#!/usr/bin/env bash
# sync-extensions — à la carte skill selector.
# Pick individual skills from the warehouse (manifest plugins + standalone +
# library/ local skills) to install or remove, instead of syncing everything.
#
# Usage:
#   bash use.sh                 # list catalog (alias: list)
#   bash use.sh list
#   bash use.sh add <id> [...]  # install selected skills
#   bash use.sh remove <id> ... # remove selected skills
#   bash use.sh installed       # show only installed
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
  spec="$("$PY" "$CAT" get "$id")" || { warn "unknown id: $id (see: use.sh list)"; return 1; }
  eval "$spec"
  case "$TYPE" in
    plugin)
      command -v claude >/dev/null || { warn "claude CLI required for $id"; return 1; }
      if [ "$INSTALLED" = "1" ]; then ok "$id already installed (plugin)"; return 0; fi
      # ensure marketplace present
      if ! "$PY" -c "import json,sys;d=json.load(open('$CLAUDE_DIR/plugins/known_marketplaces.json'));sys.exit(0 if '$MARKETPLACE' in d else 1)" 2>/dev/null; then
        [ -n "$MARKETPLACE_REPO" ] && claude plugin marketplace add "$MARKETPLACE_REPO"
      fi
      claude plugin install "$PLUGIN" -s user && ok "installed plugin $PLUGIN (restart Claude)"
      ;;
    standalone)
      command -v npx >/dev/null || { warn "npx required for $id"; return 1; }
      if [ "$INSTALLED" = "1" ]; then ok "$id already installed (standalone)"; return 0; fi
      echo "  installing standalone '$id' from $REPO (interactive picker may appear)"
      npx -y skills@latest add "$REPO" && ok "added from $REPO"
      ;;
    local)
      mkdir -p "$SKILLS_DIR"
      local link="$SKILLS_DIR/$id" target="$HERE/$LIBPATH"
      if [ -L "$link" ] || [ -e "$link" ]; then ok "$id already linked"; return 0; fi
      ln -s "$target" "$link" && ok "linked local skill $id -> $link (restart Claude)"
      ;;
    *) warn "unknown type for $id"; return 1 ;;
  esac
}

remove_one() {
  local id="$1" spec
  spec="$("$PY" "$CAT" get "$id")" || { warn "unknown id: $id"; return 1; }
  eval "$spec"
  case "$TYPE" in
    plugin)
      command -v claude >/dev/null || return 1
      claude plugin uninstall "$PLUGIN" -s user && ok "uninstalled $PLUGIN"
      ;;
    standalone|local)
      local link="$SKILLS_DIR/$id"
      if [ -L "$link" ]; then rm "$link" && ok "unlinked $id"
      elif [ -e "$link" ]; then warn "$link is not a symlink — left in place"
      else ok "$id not linked (nothing to remove)"; fi
      [ "$TYPE" = "standalone" ] && warn "standalone source stays in ~/.agents; remove there if desired"
      ;;
  esac
}

cmd="${1:-list}"; shift 2>/dev/null || true
case "$cmd" in
  list|"")   "$PY" "$CAT" list ;;
  installed) "$PY" "$CAT" json | "$PY" -c "import json,sys;[print('  ●',i['id'],'('+i['type']+')') for i in json.load(sys.stdin) if i['installed']]" ;;
  add)       [ "$#" -gt 0 ] || { echo "usage: use.sh add <id> [...]"; exit 2; }
             for id in "$@"; do add_one "$id"; done ;;
  remove|rm) [ "$#" -gt 0 ] || { echo "usage: use.sh remove <id> [...]"; exit 2; }
             for id in "$@"; do remove_one "$id"; done ;;
  json)      "$PY" "$CAT" json ;;
  *) echo "unknown command: $cmd"; echo "use: list | add <id> | remove <id> | installed"; exit 2 ;;
esac
