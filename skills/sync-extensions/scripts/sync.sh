#!/usr/bin/env bash
# sync-extensions — install + update all Claude Code plugins & standalone skills
# from manifest.json. Idempotent. Safe to re-run. Cross-platform (Linux, macOS
# incl. Apple Silicon, Windows via Git Bash/WSL).
#
# Usage:
#   sync.sh                 # full sync (add missing, install missing, update all)
#   sync.sh --dry-run       # print every command without executing
#   sync.sh --check         # report state only (no add/install/update)
#   sync.sh --list          # alias for --check (shows priority groups + selection)
#   sync.sh --all           # this run: include every optional/extra asset
#   sync.sh --base-only     # this run: install base assets only
#   sync.sh --enable a,b    # persist a,b as selected (then sync), then continue
#   sync.sh --disable a,b   # persist a,b as deselected (then sync), then continue
#
# Asset priorities (set in manifest.json):
#   base      always installed (mandatory)
#   optional  installed when selected (default-on unless deselected)
#   extra     installed when selected (default-off unless enabled)
# Selections persist in  $CLAUDE_CONFIG_DIR/.sync-extensions-selection.json
set -uo pipefail

# Re-exec under bash if launched via sh/dash (Windows users sometimes do).
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$HERE/../manifest.json"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
KNOWN="$CLAUDE_DIR/plugins/known_marketplaces.json"
INSTALLED="$CLAUDE_DIR/plugins/installed_plugins.json"
SELECTION="$CLAUDE_DIR/.sync-extensions-selection.json"
LOCK="$HOME/.agents/.skill-lock.json"

detect_os() { # -> linux | macos | windows
  case "${OSTYPE:-$(uname -s 2>/dev/null)}" in
    darwin*|Darwin*) echo macos ;;
    msys*|cygwin*|mingw*|MINGW*|MSYS*|win32) echo windows ;;
    *) echo linux ;;
  esac
}
OS="$(detect_os)"

# ---------- argument parsing ----------
MODE="full"            # full | dry | check
INCLUDE_ALL=0
BASE_ONLY=0
ENABLE_CSV=""
DISABLE_CSV=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)   MODE="dry" ;;
    --check|--list) MODE="check" ;;
    --all)       INCLUDE_ALL=1 ;;
    --base-only) BASE_ONLY=1 ;;
    --enable)    shift; ENABLE_CSV="${1:-}"; [ -n "$ENABLE_CSV" ] || { echo "--enable needs a,b,c"; exit 2; } ;;
    --disable)   shift; DISABLE_CSV="${1:-}"; [ -n "$DISABLE_CSV" ] || { echo "--disable needs a,b,c"; exit 2; } ;;
    *) echo "unknown arg: $1"; exit 2 ;;
  esac
  shift
done

PY=python3
command -v "$PY" >/dev/null || { echo "python3 required"; exit 1; }
command -v claude >/dev/null || { echo "claude CLI not on PATH"; exit 1; }
[ -f "$MANIFEST" ] || { echo "manifest not found: $MANIFEST"; exit 1; }
"$PY" -c 'import json,sys; json.load(open(sys.argv[1]))' "$MANIFEST" 2>/dev/null \
  || { echo "manifest is not valid JSON: $MANIFEST"; exit 1; }

# ---------- verification tracking ----------
WARNINGS=()
RESULTS=()              # "name|priority|action|state"
INCLUDED_NAMES=" "      # space-delimited list of included asset names
BASE_FAILED=0

warn_collect() { local m="$1"; echo "  [warn] $m"; WARNINGS+=("$m"); }
record()       { RESULTS+=("$1|$2|$3|$4"); }
is_included()  { case "$INCLUDED_NAMES" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
# collapse a success state to 'planned' when not actually executing
done_state()   { if [ "$MODE" = "full" ]; then echo "$1"; else echo "planned"; fi; }

run() {
  echo "+ $*"
  [ "$MODE" = "dry" ]   && return 0
  [ "$MODE" = "check" ] && return 0
  "$@"
}

# All python helpers below take their paths as argv (never string-interpolated)
# so they survive paths containing spaces (common on Windows/macOS).
mq() { "$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); exec(sys.argv[2])' "$MANIFEST" "$1"; }

marketplace_known() { # $1 = marketplace name
  "$PY" -c 'import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(1)
sys.exit(0 if sys.argv[2] in d else 1)' "$KNOWN" "$1" 2>/dev/null
}

plugin_installed() { # $1 = name@marketplace
  "$PY" -c 'import json,sys
try: d=json.load(open(sys.argv[1])).get("plugins",{})
except Exception: sys.exit(1)
sys.exit(0 if sys.argv[2] in d else 1)' "$INSTALLED" "$1" 2>/dev/null
}

plugin_path() { # $1 = name@marketplace -> prints installPath
  "$PY" -c 'import json,sys
try: d=json.load(open(sys.argv[1])).get("plugins",{})
except Exception: d={}
v=d.get(sys.argv[2]); print(v[0].get("installPath","") if isinstance(v,list) and v else "")' "$INSTALLED" "$1" 2>/dev/null
}

repo_in_lock() { # $1 = csv of skill names -> exit 0 if all present in lock
  "$PY" -c 'import json,sys
try: have=set(json.load(open(sys.argv[1])).get("skills",{}))
except Exception: have=set()
want=[s for s in sys.argv[2].split(",") if s]
sys.exit(0 if want and all(s in have for s in want) else 1)' "$LOCK" "$1" 2>/dev/null
}

# decide <name> <priority> <default> -> echoes 1 (include) or 0 (skip)
decide() {
  "$PY" -c 'import json,sys
sel_path,name,priority,default,inc_all,base_only=sys.argv[1:7]
if priority=="base": print(1); sys.exit()
if base_only=="1":   print(0); sys.exit()
if inc_all=="1":     print(1); sys.exit()
try: enabled=json.load(open(sel_path)).get("enabled",{})
except Exception: enabled={}
if name in enabled: print(1 if enabled[name] else 0)
else: print(1 if str(default).lower() in ("true","1","yes") else 0)' \
    "$SELECTION" "$1" "$2" "$3" "$INCLUDE_ALL" "$BASE_ONLY"
}

set_selection() { # $1 = csv names, $2 = true|false
  "$PY" -c 'import json,sys,os
path,names,val=sys.argv[1],sys.argv[2],(sys.argv[3]=="true")
d=os.path.dirname(path)
if d: os.makedirs(d, exist_ok=True)
try: data=json.load(open(path))
except Exception: data={}
data.setdefault("enabled",{}); data["version"]=1
for n in names.split(","):
    n=n.strip()
    if n: data["enabled"][n]=val
json.dump(data, open(path,"w"), indent=2)' "$SELECTION" "$1" "$2"
}

echo "=========================================="
echo " sync-extensions  (mode: $MODE, os: $OS)"
echo "=========================================="

# ---------- 0. apply selection mutations ----------
if [ -n "$ENABLE_CSV" ]; then
  echo; echo "## selection: enabling -> $ENABLE_CSV"
  set_selection "$ENABLE_CSV" true && echo "  persisted to $SELECTION"
fi
if [ -n "$DISABLE_CSV" ]; then
  echo; echo "## selection: disabling -> $DISABLE_CSV"
  set_selection "$DISABLE_CSV" false && echo "  persisted to $SELECTION"
fi

# ---------- 1. marketplaces ----------
echo
echo "## marketplaces"
while IFS=$'\t' read -r name repo; do
  [ -n "$name" ] || continue
  if [ -f "$KNOWN" ] && marketplace_known "$name"; then
    echo "  [present] $name"
  else
    echo "  [missing] $name -> adding"
    run claude plugin marketplace add "$repo"
  fi
done < <(mq "[print('\t'.join([m['name'],m['repo']])) for m in d['marketplaces']]")
if [ "$MODE" = "full" ]; then
  run claude plugin marketplace update
else
  echo "+ claude plugin marketplace update   (skipped in $MODE)"
fi

# ---------- 2. plugins (priority-gated) ----------
echo
echo "## plugins"
while IFS=$'\t' read -r name mkt priority default; do
  [ -n "$name" ] || continue
  key="$name@$mkt"
  if [ "$(decide "$name" "$priority" "$default")" != "1" ]; then
    echo "  [skipped:$priority] $key (deselected)"
    record "$name" "$priority" "skip" "skipped"
    continue
  fi
  INCLUDED_NAMES="$INCLUDED_NAMES$name "
  if [ -f "$INSTALLED" ] && plugin_installed "$key"; then
    echo "  [installed] $key -> update ($priority)"
    if run claude plugin update "$key" -s user; then
      record "$name" "$priority" "update" "$(done_state updated)"
    else
      record "$name" "$priority" "update" "failed"
      warn_collect "plugin update failed: $key"
      [ "$priority" = "base" ] && BASE_FAILED=1
    fi
  else
    echo "  [absent]    $key -> install ($priority)"
    if run claude plugin install "$key" -s user; then
      record "$name" "$priority" "install" "$(done_state installed)"
    else
      record "$name" "$priority" "install" "failed"
      warn_collect "plugin install failed: $key"
      [ "$priority" = "base" ] && BASE_FAILED=1
    fi
  fi
done < <(mq "[print('\t'.join([p['name'],p['marketplace'],p.get('priority','optional'),str(p.get('default',True))])) for p in d['plugins']]")

# ---------- 2b. basic setup (only for included plugins) ----------
echo
echo "## basic setup"

# caveman: idempotent global hooks/statusline + default level=full
if is_included caveman; then
  CAV_PATH="$(plugin_path caveman@caveman)"
  if [ -n "$CAV_PATH" ] && [ -f "$CAV_PATH/src/hooks/install.sh" ]; then
    echo "  caveman: ensuring global hooks/statusline (idempotent)"
    run bash "$CAV_PATH/src/hooks/install.sh"
  else
    warn_collect "caveman hook installer not found (path: ${CAV_PATH:-none})"
  fi
  if [ -f "$CLAUDE_DIR/.caveman-active" ]; then
    echo "  caveman: level = $(cat "$CLAUDE_DIR/.caveman-active") (kept)"
  else
    echo "  caveman: setting default level = full"
    if [ "$MODE" = "full" ]; then printf 'full' > "$CLAUDE_DIR/.caveman-active"; fi
  fi
else
  echo "  caveman: skipped (deselected)"
fi

# karpathy: verify plugin skill present (auto-loads via plugin system)
if is_included andrej-karpathy-skills; then
  KP_PATH="$(plugin_path andrej-karpathy-skills@karpathy-skills)"
  if [ -n "$KP_PATH" ] && [ -d "$KP_PATH/skills/karpathy-guidelines" ]; then
    echo "  karpathy: skill 'karpathy-guidelines' present [ok]"
  else
    warn_collect "karpathy skill not found (path: ${KP_PATH:-none}/skills/karpathy-guidelines)"
  fi
else
  echo "  karpathy: skipped (deselected)"
fi

# headroom: ensure the 'headroom' CLI is on PATH so the plugin's SessionStart/
# PreToolUse hook ('headroom init hook ensure') can auto-init the runtime.
if is_included headroom; then
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
        warn_collect "headroom auto-install failed — install manually: pip install \"headroom-ai[all]\""
      fi
      # Search common bin dirs across platforms and symlink the first hit onto
      # PATH (~/.local/bin). On M1, Homebrew lives under /opt/homebrew.
      if ! command -v headroom >/dev/null 2>&1; then
        UB="$("$PY" -m site --user-base 2>/dev/null)"
        SEARCH_DIRS=(
          "$UB/bin" "$UB/Scripts"
          "$("$PY" -m site --user-site 2>/dev/null)/../Scripts"
          "$(brew --prefix 2>/dev/null)/bin"
          "$(npm prefix -g 2>/dev/null)/bin"
          "$(npm bin -g 2>/dev/null)"
          "$HOME/.local/bin"
        )
        for d in "${SEARCH_DIRS[@]}"; do
          [ -n "$d" ] && [ -x "$d/headroom" ] || continue
          if [ "$OS" = "windows" ]; then
            warn_collect "headroom found at $d — add it to PATH (symlinks unreliable on Windows)"
          else
            mkdir -p "$HOME/.local/bin"
            ln -sf "$d/headroom" "$HOME/.local/bin/headroom"
            echo "  headroom: linked $d/headroom -> ~/.local/bin/headroom"
          fi
          break
        done
      fi
      hash -r 2>/dev/null || true
      if command -v headroom >/dev/null 2>&1; then
        echo "  headroom: on PATH [ok] — init hook will auto-run next session"
      else
        prof="~/.zshrc"; [ "$OS" = "linux" ] && prof="~/.bashrc"
        warn_collect "headroom not on PATH — add ~/.local/bin (or the dir above) to PATH in $prof"
      fi
    else
      echo "+ pip install \"headroom-ai[all]\"   (skipped in $MODE)"
    fi
  fi
else
  echo "  headroom: skipped (deselected)"
fi

# ---------- 3. standalone skills (vercel skills CLI, priority-gated) ----------
echo
echo "## standalone skills (skills CLI)"
HAVE_NPX=1; command -v npx >/dev/null 2>&1 || HAVE_NPX=0
if [ "$HAVE_NPX" = "0" ]; then
  warn_collect "npx/node not found — skipping standalone skills (install Node >=18)"
else
  while IFS=$'\t' read -r name repo priority default skills; do
    [ -n "$name" ] || continue
    if [ "$(decide "$name" "$priority" "$default")" != "1" ]; then
      echo "  [skipped:$priority] $name ($repo) (deselected)"
      record "$name" "$priority" "skip" "skipped"
      continue
    fi
    INCLUDED_NAMES="$INCLUDED_NAMES$name "
    if [ -f "$LOCK" ] && repo_in_lock "$skills"; then
      echo "  [present] $name ($repo) -> will update ($priority)"
      record "$name" "$priority" "update" "$(done_state updated)"
    else
      echo "  [absent]  $name ($repo) -> add ($priority)"
      # Pass --skill so repos sharing one source (e.g. mattpocock/skills split
      # into grill + arch entries) install only their own subset, honoring
      # per-entry priority. A whole-repo add would pull deselected siblings.
      if run npx -y skills@latest add "$repo" --skill "$skills"; then
        record "$name" "$priority" "add" "$(done_state installed)"
      else
        record "$name" "$priority" "add" "failed"
        warn_collect "skills add failed: $repo"
        [ "$priority" = "base" ] && BASE_FAILED=1
      fi
    fi
  done < <(mq "[print('\t'.join([r['name'],r['repo'],r.get('priority','optional'),str(r.get('default',True)),','.join(r.get('skills',[]))])) for r in d['standalone_skills']['repos']]")

  # Refresh everything already tracked in the lock.
  if [ -f "$LOCK" ]; then
    if [ "$MODE" = "full" ]; then
      if ! run npx -y skills@latest update; then
        warn_collect "'skills update' unavailable/failed — re-add manually (see manifest)"
      fi
    else
      echo "+ npx skills@latest update   (skipped in $MODE)"
    fi
  fi
fi

# ---------- 4. installed plugin versions ----------
echo
echo "## installed plugin versions"
[ -f "$INSTALLED" ] && "$PY" -c 'import json,sys
d=json.load(open(sys.argv[1])).get("plugins",{})
for k,v in d.items():
    e=v[0] if isinstance(v,list) and v else {}
    print("  %-45s %s" % (k, e.get("version","?")))' "$INSTALLED"

# ---------- 5. verification summary ----------
echo
echo "## verification summary"
printf '  %-30s %-9s %-8s %s\n' "ASSET" "PRIORITY" "ACTION" "STATE"
printf '  %s\n' "------------------------------------------------------------"
for r in "${RESULTS[@]:-}"; do
  [ -n "$r" ] || continue
  IFS='|' read -r n p a s <<<"$r"
  printf '  %-30s %-9s %-8s %s\n' "$n" "$p" "$a" "$s"
done
if [ "${#WARNINGS[@]}" -gt 0 ]; then
  echo
  echo "  warnings (${#WARNINGS[@]}):"
  for w in "${WARNINGS[@]}"; do echo "    - $w"; done
fi

echo
echo "=========================================="
echo " done. RESTART Claude Code to apply plugin"
echo " updates (plugin changes load next session)."
echo "=========================================="

# Non-zero exit only if a BASE (mandatory) asset failed; optional/extra
# failures are tolerated (network/offline, etc.).
[ "$BASE_FAILED" = "1" ] && { echo "ERROR: a base (mandatory) asset failed — see warnings above."; exit 1; }
exit 0
