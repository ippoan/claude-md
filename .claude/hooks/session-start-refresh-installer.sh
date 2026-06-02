#!/bin/bash
# SessionStart hook: auto-refresh installer.
#
# CCoW environment cache が一度 install.sh を焼き付けてから二度と setup
# script を走らせない問題を解決するため、毎 session 起動時に main の
# install.sh を fetch して disk 上の last-installed sha と比較し、変わって
# いれば再 run する。これで user は CCoW Setup script を初回 paste した後
# 二度と編集しないで済む。
#
# 比較する sha は install.sh 単独ではなく **install.sh ++ settings.json.template
# の合成 sha**。install.sh は settings.json.template を展開するだけで template の
# 中身を自身に埋め込まないため、template だけ変えた PR (新規 hook の登録や env
# 追加。例: claude-md #64/#65) は install.sh の sha を変えず、warm container に
# 伝播しない (issue ippoan/claude-hooks#8)。template を合成 sha に畳み込むことで
# client 側でもこれを検知する。hook の *中身* の変更は install.sh が埋め込む
# HOOK_SHAS block 経由で install.sh の sha に既に反映されるので、合成には
# install.sh + template の 2 つで十分 (hooks は推移的にカバーされる)。
# stamp-install-sh-version.yml の path filter にも template を追加してあり
# (server 側の対策)、本 hook の合成 sha はその belt-and-suspenders。
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
#   CLAUDE_MD_BASE_URL       claude-md raw base URL (default: main raw base)
#                            INSTALL/TEMPLATE URL 未指定時の派生元
#   CLAUDE_MD_INSTALL_URL    install.sh URL (default: $CLAUDE_MD_BASE_URL/.claude/install.sh)
#   CLAUDE_MD_TEMPLATE_URL   settings.json.template URL
#                            (default: $CLAUDE_MD_BASE_URL/.claude/settings.json.template)
#   CLAUDE_REFRESH_MARKER    last-installed 合成 sha marker path
#                            (default: $CLAUDE_HOME/.refresh-installer-marker)
#   CLAUDE_REFRESH_TTL       network check skip TTL 秒 (default: 300 = 5 min)
set -u

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
BASE_URL="${CLAUDE_MD_BASE_URL:-https://raw.githubusercontent.com/ippoan/claude-md/main}"
INSTALLER_URL="${CLAUDE_MD_INSTALL_URL:-$BASE_URL/.claude/install.sh}"
TEMPLATE_URL="${CLAUDE_MD_TEMPLATE_URL:-$BASE_URL/.claude/settings.json.template}"
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
TMPL_FILE=$(mktemp 2>/dev/null || echo "/tmp/refresh-installer-tmpl-$$.json")
trap 'rm -f "$TMPFILE" "$TMPL_FILE"' EXIT

if ! curl -fsSL --max-time 15 "$INSTALLER_URL" -o "$TMPFILE" 2>/dev/null; then
  emit "refresh-installer: fetch failed ($INSTALLER_URL) — keep current state"
  exit 0
fi
if ! curl -fsSL --max-time 15 "$TEMPLATE_URL" -o "$TMPL_FILE" 2>/dev/null; then
  emit "refresh-installer: template fetch failed ($TEMPLATE_URL) — keep current state"
  exit 0
fi

# Composite marker: sha256 over install.sh ++ settings.json.template (in that
# byte order). Catches template-only changes (new hook registration / env
# additions) that leave install.sh's own sha unchanged. The concatenation
# order MUST match install.sh's Section 9 marker write or every session would
# spuriously re-run install.sh.
new_sha=$(cat "$TMPFILE" "$TMPL_FILE" 2>/dev/null | sha256sum 2>/dev/null | awk '{print $1}')
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
  emit "refresh-installer: install.sh + template unchanged (sha ${new_sha:0:12})"
  exit 0
fi

# Re-run install.sh. stdout → stderr so hook stdout stays clean for emit JSON.
if bash "$TMPFILE" >&2; then
  echo "$new_sha" > "$MARKER"
  emit "refresh-installer: re-ran install.sh (new sha ${new_sha:0:12}, was ${last_sha:0:12})"
else
  emit "refresh-installer: install.sh failed (sha ${new_sha:0:12}) — kept old state"
fi
