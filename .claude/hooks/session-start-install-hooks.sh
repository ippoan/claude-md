#!/bin/bash
# SessionStart hook: install ippoan/claude-skills + ippoan/claude-hooks
# (via the CCoW per-session git proxy) and anthropics/skills (via the
# proxy with a github.com fallback) — all symlinked into ~/.claude/skills.
#
# Why anthropics/skills is cloned locally:
#   Claude Code on Web (Cowork) runs in ephemeral containers and does
#   NOT mount UI-installed Anthropic skills (skill-creator, mcp-builder,
#   canvas-design, etc.) into the container, even when claude.ai shows
#   them as installed. See anthropics/claude-code issues #31542, #26254,
#   #50669. Cloning the public anthropics/skills repo here is the only
#   reliable way to make those skills available inside each session.
#
# CCoW container 内では attached repo が
#   http://local_proxy@127.0.0.1:<port>/git/<owner>/<repo>
# 経由で clone されており、この proxy は ippoan/* repo にも access 可能
# なため、attached repo の .git/config から proxy URL を抜き出して
# claude-skills / claude-hooks の bootstrap に流用する。
# 同じ proxy 経由で anthropics/skills (public) も取得する。proxy が
# 公開 repo を許可しない構成のケースに備え、github.com 直 URL に fallback。
#
# Conflict policy: ippoan/claude-skills が先に処理され名前衝突で勝つ。
# anthropics/skills は空きスロットだけを埋める (user override を温存)。
#
# 出力: SessionStart hook spec の JSON (additionalContext で結果を inject)
#   1 行目: install-hooks の総数 + status
#   2 行目: key-skills の名指し ✓/✗ (／ menu に出てるか即判定するため)
#
# env override:
#   CLAUDE_HOME              ~/.claude の path (default: $HOME/.claude)
#   CLAUDE_HOOKS_INSTALL_TTL network sync を skip する TTL 秒 (default: 3600)
#   CLAUDE_HOOKS_SCAN_DIRS   proxy URL を探す attached repo の親 dir (default: /home/user)
#   CLAUDE_HOOKS_ANTHROPIC_SKILLS_DIRECT
#                            anthropics/skills の直 clone URL fallback
#                            (default: https://github.com/anthropics/skills.git)
#   CLAUDE_HOOKS_KEY_SKILLS  ✓/✗ check 対象 skill 名の space 区切りリスト
#                            (default: "skill-creator open-multirepo")
set -u

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
SOURCES_DIR="$CLAUDE_HOME/sources"
SKILLS_DIR="$CLAUDE_HOME/skills"
TTL="${CLAUDE_HOOKS_INSTALL_TTL:-3600}"
SCAN_DIRS="${CLAUDE_HOOKS_SCAN_DIRS:-/home/user}"
KEY_SKILLS="${CLAUDE_HOOKS_KEY_SKILLS:-skill-creator open-multirepo}"
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
ANTHROPIC_DIRECT_URL="${CLAUDE_HOOKS_ANTHROPIC_SKILLS_DIRECT:-https://github.com/anthropics/skills.git}"

clone_or_pull() {
  local owner=$1 repo=$2 dest_name="${3:-$2}" fallback_url="${4:-}"
  local dest="$SOURCES_DIR/$dest_name"
  local url="$PROXY_BASE/$owner/$repo"
  if [ -d "$dest/.git" ]; then
    if [ "$fresh" = "1" ]; then
      git -C "$dest" remote set-url origin "$url" 2>/dev/null || true
      git -C "$dest" fetch --depth 1 --quiet origin 2>/dev/null \
        && git -C "$dest" reset --hard --quiet '@{u}' 2>/dev/null \
        || notes="${notes}pull-$dest_name-failed "
    fi
  else
    if ! git clone --depth 1 --quiet "$url" "$dest" 2>/dev/null; then
      if [ -n "$fallback_url" ] && git clone --depth 1 --quiet "$fallback_url" "$dest" 2>/dev/null; then
        notes="${notes}clone-$dest_name-via-fallback "
      else
        notes="${notes}clone-$dest_name-failed "
      fi
    fi
  fi
}

clone_or_pull ippoan        claude-skills
clone_or_pull ippoan        claude-hooks
clone_or_pull anthropics    skills        anthropic-skills "$ANTHROPIC_DIRECT_URL"

# 3. SKILL.md を symlink (既存の非 symlink = user 手書きは触らない)
#    Sources are processed in order; ippoan/claude-skills owns its
#    slots (re-linked even if a symlink already exists), anthropics/skills
#    only fills slots that are still empty.
skill_count=0

# args: <source-dir> <allow-relink: 1|0>
link_skills_from() {
  local source_dir=$1 allow_relink=$2
  [ -d "$source_dir" ] || return 0
  while IFS= read -r skill_md; do
    local name target dir
    dir="$(dirname "$skill_md")"
    name="$(basename "$dir")"
    target="$SKILLS_DIR/$name"
    if [ -L "$target" ]; then
      if [ "$allow_relink" = "1" ]; then
        ln -sfn "$dir" "$target" 2>/dev/null \
          && skill_count=$((skill_count + 1))
      fi
    elif [ ! -e "$target" ]; then
      ln -s "$dir" "$target" 2>/dev/null \
        && skill_count=$((skill_count + 1))
    fi
  done < <(find "$source_dir" -name SKILL.md -not -path '*/.git/*' 2>/dev/null)
}

link_skills_from "$SOURCES_DIR/claude-skills"    1
link_skills_from "$SOURCES_DIR/anthropic-skills" 0

# 4. Key-skill availability check — name-by-name ✓/✗ so the user can tell
#    BEFORE opening the / menu whether the expected skills are present.
#    "Present" = a symlink or directory under SKILLS_DIR with a SKILL.md
#    inside (matches Claude Code's own discovery rule).
key_status=""
missing=0
for key in $KEY_SKILLS; do
  if [ -f "$SKILLS_DIR/$key/SKILL.md" ]; then
    key_status="${key_status}${key} ✓ "
  else
    key_status="${key_status}${key} ✗ "
    missing=$((missing + 1))
  fi
done
key_status="${key_status% }"
[ "$missing" -gt 0 ] && key_status="$key_status ← / menu reload needed"

[ "$fresh" = "1" ] && touch "$MARKER"

if [ "$fresh" = "1" ]; then
  msg="install-hooks: synced via proxy (skills=$skill_count) ${notes:-ok}"
else
  msg="install-hooks: within TTL ${TTL}s (skills=$skill_count, network skipped)"
fi
emit "$msg
key-skills: $key_status"
