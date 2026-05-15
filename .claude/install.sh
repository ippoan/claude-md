#!/bin/bash
# Bootstrap script for Claude Code on the Web sessions.
#
# 4 段階で user-level セットアップを行う (各段階は env で個別 skip 可能):
#
#   1. ~/.claude/settings.json                          (claude-md の template, SessionStart + PreToolUse hook 登録済)
#   2. ~/.claude/hooks/*.sh                             (session-start-install-hooks / session-start-snapshot / pre-tool-claude-dir-drift)
#   3. cc-relay shallow clone                           (ippoan/cc-relay)
#   4. cc-relay MCP server を user-level ~/.claude.json に登録
#
# skills/hooks 自体の clone は SessionStart hook が CCoW の per-session git proxy
# 経由で行う (= PAT/INTERNAL_SHARED_SECRET 不要、private repo にも access 可能)。
# Setup script 段階で attached repo はまだ無いため hook 化が必要。
#
# usage (CCoW environment Setup script 欄に 1 行貼る):
#   curl -fsSL https://raw.githubusercontent.com/ippoan/claude-md/main/.claude/install.sh | bash
#
# 直接叩いてもよい:
#   bash .claude/install.sh
#
# env override (全て optional):
#   CLAUDE_MD_BASE_URL       claude-md の raw base URL。branch 切替の単一窓口
#                            (default: https://raw.githubusercontent.com/ippoan/claude-md/main)
#                            例: PR テスト用に branch を指す場合
#                              CLAUDE_MD_BASE_URL=https://raw.githubusercontent.com/ippoan/claude-md/claude/readme-setup-script
#   CLAUDE_MD_TEMPLATE_URL   settings.json template の URL (BASE_URL を上書き)
#   CLAUDE_HOOK_URL          SessionStart hook script の URL (BASE_URL を上書き)
#   CLAUDE_HOME              ~/.claude の path (default: /root/.claude)
#   CLAUDE_SETTINGS_DEST     settings.json の install 先 (default: $CLAUDE_HOME/settings.json)
#   CLAUDE_JSON_DEST         ~/.claude.json の path (default: /root/.claude.json)
#   CC_RELAY_REPO            cc-relay の clone URL
#   CC_RELAY_DIR             cc-relay の clone 先 (default: /home/user/cc-relay, 無ければ $HOME/cc-relay)
#   CC_RELAY_MCP_URL         user-level に登録する MCP server URL (default: prod)
#   SKIP_SETTINGS=1          1 を立てると settings.json install を skip
#   SKIP_HOOK=1              1 を立てると SessionStart hook script の配置を skip
#   SKIP_CC_RELAY=1          1 を立てると cc-relay clone を skip
#   SKIP_MCP=1               1 を立てると MCP 登録を skip
#   CLAUDE_INSTALL_STAMP     stamp ファイル path (default: $CLAUDE_HOME/.install-stamp)
#                            このファイルの mtime と中身で「今 session で install.sh が
#                            走ったか / cache 由来か」を即判定できる (fresh-env 検証用)
set -eu

CLAUDE_HOME="${CLAUDE_HOME:-/root/.claude}"
CLAUDE_MD_BASE_URL="${CLAUDE_MD_BASE_URL:-https://raw.githubusercontent.com/ippoan/claude-md/main}"
TEMPLATE_URL="${CLAUDE_MD_TEMPLATE_URL:-$CLAUDE_MD_BASE_URL/.claude/settings.json.template}"
SETTINGS_DEST="${CLAUDE_SETTINGS_DEST:-$CLAUDE_HOME/settings.json}"

# Hook scripts to install under $CLAUDE_HOME/hooks/. Add new entries here
# whenever settings.json.template registers another script. CLAUDE_HOOK_URL
# (legacy) can still override the first one for backwards compatibility.
HOOK_SCRIPTS=(
  "session-start-install-hooks.sh"
  "session-start-snapshot.sh"
  "pre-tool-claude-dir-drift.sh"
)
LEGACY_HOOK_URL="${CLAUDE_HOOK_URL:-}"
CLAUDE_JSON_DEST="${CLAUDE_JSON_DEST:-/root/.claude.json}"
CC_RELAY_REPO="${CC_RELAY_REPO:-https://github.com/ippoan/cc-relay.git}"
if [ -z "${CC_RELAY_DIR:-}" ]; then
  if [ -d /home/user ]; then
    CC_RELAY_DIR=/home/user/cc-relay
  else
    CC_RELAY_DIR="${HOME:-/root}/cc-relay"
  fi
fi
CC_RELAY_MCP_URL="${CC_RELAY_MCP_URL:-https://mcp.ippoan.org/mcp}"

log() { echo "[install.sh] $*"; }

# --- 1. settings.json ---
if [ "${SKIP_SETTINGS:-0}" = "1" ]; then
  log "skip: SKIP_SETTINGS=1"
else
  mkdir -p "$(dirname "$SETTINGS_DEST")"
  curl -fsSL "$TEMPLATE_URL" -o "$SETTINGS_DEST"
  ALLOW=$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["permissions"]["allow"]))' "$SETTINGS_DEST")
  log "settings.json: $SETTINGS_DEST (allow=$ALLOW)"
fi

# --- 2. Hook scripts (SessionStart + PreToolUse) ---
if [ "${SKIP_HOOK:-0}" = "1" ]; then
  log "skip: SKIP_HOOK=1"
else
  mkdir -p "$CLAUDE_HOME/hooks"
  for name in "${HOOK_SCRIPTS[@]}"; do
    dest="$CLAUDE_HOME/hooks/$name"
    if [ "$name" = "session-start-install-hooks.sh" ] && [ -n "$LEGACY_HOOK_URL" ]; then
      url="$LEGACY_HOOK_URL"
    else
      url="$CLAUDE_MD_BASE_URL/.claude/hooks/$name"
    fi
    curl -fsSL "$url" -o "$dest"
    chmod +x "$dest"
    log "hook: $dest"
  done
fi

# --- 3. cc-relay shallow clone ---
if [ "${SKIP_CC_RELAY:-0}" = "1" ]; then
  log "skip: SKIP_CC_RELAY=1"
elif [ -d "$CC_RELAY_DIR/.git" ]; then
  log "cc-relay: already present at $CC_RELAY_DIR (skip clone)"
else
  if git ls-remote --exit-code "$CC_RELAY_REPO" HEAD >/dev/null 2>&1; then
    log "cc-relay: shallow cloning $CC_RELAY_REPO -> $CC_RELAY_DIR"
    mkdir -p "$(dirname "$CC_RELAY_DIR")"
    git clone --depth 1 "$CC_RELAY_REPO" "$CC_RELAY_DIR" || log "warn: cc-relay clone failed (continuing)"
  else
    log "skip: cc-relay not accessible ($CC_RELAY_REPO)"
  fi
fi

# --- 4. cc-relay MCP server (user-level ~/.claude.json) ---
if [ "${SKIP_MCP:-0}" = "1" ]; then
  log "skip: SKIP_MCP=1"
else
  mkdir -p "$(dirname "$CLAUDE_JSON_DEST")"
  python3 - "$CLAUDE_JSON_DEST" "$CC_RELAY_MCP_URL" <<'PY'
import json, os, sys
path, url = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
servers = data.setdefault("mcpServers", {})
servers["cc-relay"] = {"type": "http", "url": url}
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
os.replace(tmp, path)
print(f"[install.sh] MCP: registered cc-relay ({url}) in {path}")
PY
fi

log "done"

# --- 5. Install stamp (always written last) ---
# fresh-env 検証用の epoch + ISO timestamp + script SHA + base URL を
# $CLAUDE_HOME/.install-stamp に書き出す。次の session で `cat` 1 発で
# 「setup script で install.sh が走ったか」「いつの版か」を即判定できる。
# CCoW env cache snapshot に焼き込まれた古い ~/.claude を踏むと
# このファイルが container 起動より大きく前の mtime を持つ (= cache 由来)。
STAMP_DEST="${CLAUDE_INSTALL_STAMP:-$CLAUDE_HOME/.install-stamp}"
STAMP_SHA=$(sha256sum "$0" 2>/dev/null | awk '{print $1}' || echo "unknown")
STAMP_NOW_EPOCH=$(date +%s)
STAMP_NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
mkdir -p "$(dirname "$STAMP_DEST")"
cat > "$STAMP_DEST" <<STAMP
epoch=$STAMP_NOW_EPOCH
iso=$STAMP_NOW_ISO
base_url=$CLAUDE_MD_BASE_URL
script_sha256=$STAMP_SHA
hooks_installed=$([ "${SKIP_HOOK:-0}" = "1" ] && echo "skipped" || printf '%s,' "${HOOK_SCRIPTS[@]}" | sed 's/,$//')
STAMP
log "stamp: $STAMP_DEST ($STAMP_NOW_ISO)"
