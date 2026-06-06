#!/usr/bin/env bash
# Publish — commit warehouse changes and push to git.
#
# The warehouse (skills/*) is the source of truth, so authoring/editing a skill
# is just editing files here. This script additionally refreshes the standalone
# skill seed (seeds/agents) from the live ~/.agents so a fresh-machine bootstrap
# stays current, then commits everything and pushes.
#
# Usage:
#   bash publish.sh                       # auto message + push
#   bash publish.sh "feat: add foo"       # custom message + push
#   bash publish.sh --no-push "msg"       # commit only
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_DIR="$HOME/.agents"
SEEDS="$HERE/seeds/agents"

PUSH=1
[ "${1:-}" = "--no-push" ] && { PUSH=0; shift; }
MSG="${1:-chore: publish warehouse}"

ok(){ printf '  \033[32m✓\033[0m %s\n' "$*"; }
command -v git >/dev/null || { echo "git required"; exit 1; }

# refresh standalone seed from live (best-effort)
if [ -d "$AGENTS_DIR/skills" ]; then
  rm -rf "$SEEDS/skills"; mkdir -p "$SEEDS/skills"
  cp -R "$AGENTS_DIR/skills/." "$SEEDS/skills/"
  [ -f "$AGENTS_DIR/.skill-lock.json" ] && cp "$AGENTS_DIR/.skill-lock.json" "$SEEDS/.skill-lock.json"
  ok "refreshed seeds/agents from live"
fi

cd "$HERE"
git add -A
if git diff --cached --quiet; then
  echo "no changes to publish."
  exit 0
fi
git diff --cached --stat | sed 's/^/  /'
git -c user.name="${GIT_AUTHOR_NAME:-$(git config user.name || echo Claude)}" \
    -c user.email="${GIT_AUTHOR_EMAIL:-$(git config user.email || echo noreply@anthropic.com)}" \
    commit -q -m "$MSG"
ok "committed: $MSG"

if [ "$PUSH" = "1" ]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  git push -q origin "$BRANCH" && ok "pushed to origin/$BRANCH"
else
  echo "  (--no-push) commit only."
fi
