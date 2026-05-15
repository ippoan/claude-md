#!/bin/bash
# SessionStart hook: auto-refresh installer.
#
# CCoW environment cache が一度 install.sh を焼き付けてから二度と setup
# script を走らせない問題を解決するため、毎 session 起動時に main の
# install.sh を fetch して disk 上の last-installed sha と比較し、変わって
# いれば再 run する。これで user は CCoW Setup script を初回 paste した後
# 二度と編集しないで済む。
#
# 即時反映されるもの (file は session 中の hook 呼び出し時に毎回 disk 読み):
#   - ~/.claude/hooks/*.sh
#   - ~/.claude/skills/ + sources/
#   - /home/user/cc-relay clone (file system)
#   - ~/.claude/.install-stamp (検証用)
#
# 1 session 遅延するもの (Claude Code が起動時 1 度だけ read):
#   - ~/.claude/settings.json の permissions
#   - ~/.claude/settings.json の hook 登録 (= 新規 hook 追加は次 session)
#   - ~/.claude.json の mcpServers
#
# refs:
#   - https://code.claude.com/docs/en/claude-code-on-the-web (Setup script cache の挙動)
#   - https://github.com/anthropics/claude-code/issues/30737 (in-session reload feature request)
#   - https://github.com/anthropics/claude-code/issues/5513 (/reloadSettings feature request)
#
# env override:
#   CLAUDE_HOME              ~/.claude path (default: $HOME/.claude)
#   CLAUDE_MD_INSTALL_URL    install.sh URL (default: main raw URL)
#   CLAUDE_REFRESH_MARKER    last-installed sha marker path
#                            (default: $CLAUDE_HOME/.refresh-installer-marker)
#   CLAUDE_REFRESH_TTL       network check skip TTL 秒 (default: 300 = 5 min)
set -u

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
INSTALLER_URL="${CLAUDE_MD_INSTALL_URL:-https://raw.githubusercontent.com/ippoan/claude-md/main/.claude/install.sh}"
MARKER="${CLAUDE_REFRESH_MARKER:-$CLAUDE_HOME/.refresh-installer-marker}"
TTL="${CLAUDE_REFRESH_TTL:-300}"

emit() {
  python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.argv[1]}}))' "$1"
}

# TTL guard: skip network check if marker is fresh.
if [ -f "$MARKER" ]; then
  last_mtime=$(stat -c %Y "$MARKER" 2>/dev/null || echo 0)
  now=$(date +%s)
  if [ $((now - last_mtime)) -lt "$TTL" ]; then
    emit "refresh-installer: within TTL ${TTL}s (last check $((now - last_mtime))s ago)"
    exit 0
  fi
fi

TMPFILE=$(mktemp 2>/dev/null || echo "/tmp/refresh-installer-$$.sh")
trap 'rm -f "$TMPFILE"' EXIT

if ! curl -fsSL --max-time 15 "$INSTALLER_URL" -o "$TMPFILE" 2>/dev/null; then
  emit "refresh-installer: fetch failed ($INSTALLER_URL) — keep current state"
  exit 0
fi

new_sha=$(sha256sum "$TMPFILE" 2>/dev/null | awk '{print $1}')
if [ -z "$new_sha" ]; then
  emit "refresh-installer: could not compute sha — keep current state"
  exit 0
fi

last_sha=""
if [ -f "$MARKER" ]; then
  last_sha=$(head -1 "$MARKER" 2>/dev/null | tr -d '[:space:]')
fi

if [ "$new_sha" = "$last_sha" ]; then
  touch "$MARKER"
  emit "refresh-installer: install.sh unchanged (sha ${new_sha:0:12})"
  exit 0
fi

# Re-run install.sh. stdout → stderr so hook stdout stays clean for emit JSON.
if bash "$TMPFILE" >&2; then
  echo "$new_sha" > "$MARKER"
  emit "refresh-installer: re-ran install.sh (new sha ${new_sha:0:12}, was ${last_sha:0:12})"
else
  emit "refresh-installer: install.sh failed (sha ${new_sha:0:12}) — kept old state"
fi
