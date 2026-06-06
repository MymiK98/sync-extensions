#!/usr/bin/env bash
# sync-extensions — capture the current LIVE state into this bundle and push.
#
# Run this after you add/remove a skill or plugin so the git repo reflects it.
# It copies:
#   ~/.claude/skills/sync-extensions/   -> skill/        (manifest, sync.sh, SKILL.md)
#   ~/.agents/skills/ + .skill-lock.json -> agents-seed/ (standalone skills snapshot)
# then commits and pushes.
#
# Usage:
#   bash publish.sh                       # auto commit message
#   bash publish.sh "feat: add foo skill" # custom message
#   bash publish.sh --no-push "msg"       # commit only, don't push
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
AGENTS_DIR="$HOME/.agents"
LIVE_SKILL="$CLAUDE_DIR/skills/sync-extensions"

PUSH=1
[ "${1:-}" = "--no-push" ] && { PUSH=0; shift; }
MSG="${1:-chore: sync bundle from live state}"

ok(){ printf '  \033[32m✓\033[0m %s\n' "$*"; }

[ -d "$LIVE_SKILL" ] || { echo "live skill not found: $LIVE_SKILL — run bootstrap.sh first"; exit 1; }
command -v git >/dev/null || { echo "git required"; exit 1; }

# 1. capture live skill (manifest / sync.sh / SKILL.md)
rm -rf "$HERE/skill"
mkdir -p "$HERE/skill/scripts"
cp "$LIVE_SKILL/SKILL.md" "$HERE/skill/"
cp "$LIVE_SKILL/manifest.json" "$HERE/skill/"
cp "$LIVE_SKILL/scripts/sync.sh" "$HERE/skill/scripts/"
ok "captured skill/"

# 2. capture live standalone skills + lock
rm -rf "$HERE/agents-seed/skills"
mkdir -p "$HERE/agents-seed/skills"
if [ -d "$AGENTS_DIR/skills" ] && [ -n "$(ls -A "$AGENTS_DIR/skills" 2>/dev/null)" ]; then
  cp -R "$AGENTS_DIR/skills/." "$HERE/agents-seed/skills/"
  ok "captured agents-seed/skills/ ($(ls -1 "$AGENTS_DIR/skills" | wc -l | tr -d ' ') skills)"
fi
if [ -f "$AGENTS_DIR/.skill-lock.json" ]; then
  cp "$AGENTS_DIR/.skill-lock.json" "$HERE/agents-seed/.skill-lock.json"
  ok "captured .skill-lock.json"
fi

# 3. commit + push
cd "$HERE"
git add -A
if git diff --cached --quiet; then
  echo "no changes — bundle already matches live state."
  exit 0
fi
git diff --cached --stat | sed 's/^/  /'
git -c user.name="${GIT_AUTHOR_NAME:-$(git config user.name || echo Claude)}" \
    -c user.email="${GIT_AUTHOR_EMAIL:-$(git config user.email || echo noreply@anthropic.com)}" \
    commit -q -m "$MSG"
ok "committed: $MSG"

if [ "$PUSH" = "1" ]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  git push -q origin "$BRANCH"
  ok "pushed to origin/$BRANCH"
else
  echo "  (--no-push) commit only. Push later: git push origin \$(git branch --show-current)"
fi
