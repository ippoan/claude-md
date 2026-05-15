#!/bin/bash
# SessionStart hook: install yhonda-ohishi/{claude-skills,claude-hooks}
# via the CCoW per-session git proxy.
#
# CCoW container 内では attached repo が
#   http://local_proxy@127.0.0.1:<port>/git/<owner>/<repo>
# 経由で clone されており、この proxy は private repo (yhonda-ohishi/* 含む)
# にも access 可能なため、attached repo の .git/config から proxy URL を
# 抜き出して claude-skills / claude-hooks の bootstrap に流用する。
#
# 出力: SessionStart hook spec の JSON (additionalContext で結果を inject)
#
# env override:
#   CLAUDE_HOME              ~/.claude の path (default: $HOME/.claude)
#   CLAUDE_HOOKS_INSTALL_TTL network sync を skip する TTL 秒 (default: 3600)
#   CLAUDE_HOOKS_SCAN_DIRS   proxy URL を探す attached repo の親 dir (default: /home/user)
set -u

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
SOURCES_DIR="$CLAUDE_HOME/sources"
SKILLS_DIR="$CLAUDE_HOME/skills"
TTL="${CLAUDE_HOOKS_INSTALL_TTL:-3600}"
SCAN_DIRS="${CLAUDE_HOOKS_SCAN_DIRS:-/home/user}"
MARKER="$CLAUDE_HOME/.install-hooks-marker"

emit() {
  python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.argv[1]}}))' "$1"
}

# 1. attached repo の .git/config から proxy URL を抜き出す
PROXY_BASE=""
for parent in $SCAN_DIRS; do
  [ -d "$parent" ] || continue
  for d in "$parent"/*/; do
    [ -f "${d}.git/config" ] || continue
    url=$(git -C "$d" remote get-url origin 2>/dev/null || true)
    if [[ "$url" =~ ^(http://local_proxy@127\.0\.0\.1:[0-9]+/git) ]]; then
      PROXY_BASE="${BASH_REMATCH[1]}"
      break 2
    fi
  done
done

if [ -z "$PROXY_BASE" ]; then
  emit "session-start-install-hooks: no CCoW git proxy detected — skipped"
  exit 0
fi

mkdir -p "$SOURCES_DIR" "$SKILLS_DIR"

# 2. TTL check
fresh=1
if [ -f "$MARKER" ]; then
  last=$(stat -c %Y "$MARKER" 2>/dev/null || echo 0)
  now=$(date +%s)
  if [ $((now - last)) -lt "$TTL" ]; then
    fresh=0
  fi
fi

notes=""
clone_or_pull() {
  local owner=$1 repo=$2
  local dest="$SOURCES_DIR/$repo"
  local url="$PROXY_BASE/$owner/$repo"
  if [ -d "$dest/.git" ]; then
    if [ "$fresh" = "1" ]; then
      git -C "$dest" remote set-url origin "$url" 2>/dev/null || true
      git -C "$dest" fetch --depth 1 --quiet origin 2>/dev/null \
        && git -C "$dest" reset --hard --quiet '@{u}' 2>/dev/null \
        || notes="${notes}pull-$repo-failed "
    fi
  else
    git clone --depth 1 --quiet "$url" "$dest" 2>/dev/null \
      || notes="${notes}clone-$repo-failed "
  fi
}

clone_or_pull yhonda-ohishi claude-skills
clone_or_pull yhonda-ohishi claude-hooks

# 3. SKILL.md を symlink (既存の非 symlink = user 手書きは触らない)
skill_count=0
if [ -d "$SOURCES_DIR/claude-skills" ]; then
  while IFS= read -r skill_md; do
    name=$(basename "$(dirname "$skill_md")")
    target="$SKILLS_DIR/$name"
    if [ -L "$target" ] || [ ! -e "$target" ]; then
      ln -sfn "$(dirname "$skill_md")" "$target" 2>/dev/null \
        && skill_count=$((skill_count + 1))
    fi
  done < <(find "$SOURCES_DIR/claude-skills" -name SKILL.md -not -path '*/.git/*' 2>/dev/null)
fi

[ "$fresh" = "1" ] && touch "$MARKER"

if [ "$fresh" = "1" ]; then
  emit "install-hooks: synced via proxy (skills=$skill_count) ${notes:-ok}"
else
  emit "install-hooks: within TTL ${TTL}s (skills=$skill_count, network skipped)"
fi
