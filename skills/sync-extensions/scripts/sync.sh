#!/usr/bin/env bash
# sync-extensions — install + update all Claude Code plugins & standalone skills
# from manifest.json. Idempotent. Safe to re-run.
#
# Usage:
#   sync.sh             # full sync (add missing, install missing, update all)
#   sync.sh --dry-run   # print every command without executing
#   sync.sh --check     # report state only (no add/install/update)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$HERE/../manifest.json"
KNOWN="$HOME/.claude/plugins/known_marketplaces.json"
INSTALLED="$HOME/.claude/plugins/installed_plugins.json"
LOCK="$HOME/.agents/.skill-lock.json"

MODE="full"
case "${1:-}" in
  --dry-run) MODE="dry" ;;
  --check)   MODE="check" ;;
  "" )       MODE="full" ;;
  *) echo "unknown arg: $1"; exit 2 ;;
esac

PY=python3
command -v "$PY" >/dev/null || { echo "python3 required"; exit 1; }
command -v claude >/dev/null || { echo "claude CLI not on PATH"; exit 1; }
[ -f "$MANIFEST" ] || { echo "manifest not found: $MANIFEST"; exit 1; }

run() {
  echo "+ $*"
  [ "$MODE" = "dry" ] && return 0
  [ "$MODE" = "check" ] && return 0
  "$@"
}

mq() { "$PY" -c "import json,sys; d=json.load(open('$MANIFEST')); $1"; }

echo "=========================================="
echo " sync-extensions  (mode: $MODE)"
echo "=========================================="

# ---------- 1. marketplaces ----------
echo
echo "## marketplaces"
mq "[print(m['name'],m['repo']) for m in d['marketplaces']]" | while read -r name repo; do
  if [ -f "$KNOWN" ] && "$PY" -c "import json,sys; sys.exit(0 if '$name' in json.load(open('$KNOWN')) else 1)" 2>/dev/null; then
    echo "  [present] $name"
  else
    echo "  [missing] $name -> adding"
    run claude plugin marketplace add "$repo"
  fi
done
if [ "$MODE" = "full" ]; then
  run claude plugin marketplace update
else
  echo "+ claude plugin marketplace update   (skipped in $MODE)"
fi

# ---------- 2. plugins ----------
echo
echo "## plugins"
mq "[print(p['name'],p['marketplace']) for p in d['plugins']]" | while read -r name mkt; do
  key="$name@$mkt"
  if [ -f "$INSTALLED" ] && "$PY" -c "import json,sys; d=json.load(open('$INSTALLED')); sys.exit(0 if '$key' in d.get('plugins',{}) else 1)" 2>/dev/null; then
    echo "  [installed] $key -> update"
    run claude plugin update "$key" -s user
  else
    echo "  [absent]    $key -> install"
    run claude plugin install "$key" -s user
  fi
done

# ---------- 2b. basic setup (caveman, karpathy, headroom) ----------
echo
echo "## basic setup"

plugin_path() {  # $1 = name@marketplace -> prints installPath
  "$PY" -c "
import json
d=json.load(open('$INSTALLED')).get('plugins',{})
v=d.get('$1')
print(v[0].get('installPath','') if isinstance(v,list) and v else '')
" 2>/dev/null
}

# caveman: idempotent global hooks/statusline + default level=full
CAV_PATH="$(plugin_path caveman@caveman)"
if [ -n "$CAV_PATH" ] && [ -f "$CAV_PATH/src/hooks/install.sh" ]; then
  echo "  caveman: ensuring global hooks/statusline (idempotent)"
  run bash "$CAV_PATH/src/hooks/install.sh"
else
  echo "  [warn] caveman hook installer not found (path: ${CAV_PATH:-none})"
fi
if [ -f "$HOME/.claude/.caveman-active" ]; then
  echo "  caveman: level = $(cat "$HOME/.claude/.caveman-active") (kept)"
else
  echo "  caveman: setting default level = full"
  if [ "$MODE" = "full" ]; then printf 'full' > "$HOME/.claude/.caveman-active"; fi
fi

# karpathy: verify plugin skill present (auto-loads via plugin system)
KP_PATH="$(plugin_path andrej-karpathy-skills@karpathy-skills)"
if [ -n "$KP_PATH" ] && [ -d "$KP_PATH/skills/karpathy-guidelines" ]; then
  echo "  karpathy: skill 'karpathy-guidelines' present [ok]"
else
  echo "  [warn] karpathy skill not found (path: ${KP_PATH:-none}/skills/karpathy-guidelines)"
fi

# headroom: ensure the 'headroom' CLI is on PATH so the plugin's SessionStart/
# PreToolUse hook ('headroom init hook ensure') can auto-init the runtime.
if command -v headroom >/dev/null 2>&1; then
  echo "  headroom: CLI present ($(headroom --version 2>/dev/null | head -1)) [ok]"
else
  echo "  headroom: CLI missing -> installing (so init hook works)"
  if [ "$MODE" = "full" ]; then
    if command -v pipx >/dev/null 2>&1 && pipx install "headroom-ai[all]" 2>/dev/null; then
      echo "  headroom: installed via pipx"
    elif "$PY" -m pip install --user "headroom-ai[all]" 2>/dev/null; then
      echo "  headroom: installed via pip --user"
    elif command -v npm >/dev/null 2>&1 && npm install -g headroom-ai 2>/dev/null; then
      echo "  headroom: installed via npm -g"
    else
      echo "  [warn] headroom auto-install failed — install manually:"
      echo "         pip install \"headroom-ai[all]\"   (or npm install -g headroom-ai)"
    fi
    # pip --user puts the script under site user-base/bin (often off PATH).
    # Symlink it into ~/.local/bin (commonly on PATH) so bare 'headroom' resolves.
    if ! command -v headroom >/dev/null 2>&1; then
      UB="$("$PY" -m site --user-base 2>/dev/null)"
      if [ -n "$UB" ] && [ -x "$UB/bin/headroom" ]; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$UB/bin/headroom" "$HOME/.local/bin/headroom"
        echo "  headroom: linked $UB/bin/headroom -> ~/.local/bin/headroom"
      fi
    fi
    hash -r 2>/dev/null || true
    if command -v headroom >/dev/null 2>&1; then
      echo "  headroom: on PATH [ok] — init hook will auto-run next session"
    else
      echo "  [warn] headroom not on PATH — add ~/.local/bin (or $UB/bin) to PATH"
    fi
  else
    echo "+ pip install \"headroom-ai[all]\"   (skipped in $MODE)"
  fi
fi

# ---------- 3. standalone skills (vercel skills CLI) ----------
echo
echo "## standalone skills (skills CLI)"
if [ -f "$LOCK" ]; then
  echo "  lock present: $LOCK"
  if [ "$MODE" = "full" ]; then
    if ! run npx -y skills@latest update; then
      echo "  [warn] 'skills update' unavailable/failed — re-add each repo manually:"
      mq "[print('    npx skills@latest add '+r['repo']) for r in d['standalone_skills']['repos']]"
    fi
  else
    echo "+ npx skills@latest update   (skipped in $MODE)"
  fi
else
  echo "  no lock — installing from manifest"
  mq "[print(r['repo']) for r in d['standalone_skills']['repos']]" | while read -r repo; do
    run npx -y skills@latest add "$repo"
  done
fi

# ---------- 4. report ----------
echo
echo "## installed plugin versions"
[ -f "$INSTALLED" ] && "$PY" -c "
import json
d=json.load(open('$INSTALLED')).get('plugins',{})
for k,v in d.items():
    e=v[0] if isinstance(v,list) and v else {}
    print('  %-45s %s' % (k, e.get('version','?')))
"

echo
echo "=========================================="
echo " done. RESTART Claude Code to apply plugin"
echo " updates (plugin changes load next session)."
echo "=========================================="
