#!/bin/bash
# Bootstrap script for Claude Code on the Web sessions.
#
# 4 段階で user-level セットアップを行う (各段階は env で個別 skip 可能):
#
#   1. ~/.claude/settings.json                          (claude-md の template, SessionStart hook 登録済)
#   2. ~/.claude/hooks/session-start-install-hooks.sh   (毎 session で skills/hooks を proxy 経由 sync)
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
#   CLAUDE_MD_TEMPLATE_URL   settings.json template の URL
#   CLAUDE_HOOK_URL          SessionStart hook script の URL
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
set -eu

CLAUDE_HOME="${CLAUDE_HOME:-/root/.claude}"
TEMPLATE_URL="${CLAUDE_MD_TEMPLATE_URL:-https://raw.githubusercontent.com/ippoan/claude-md/main/.claude/settings.json.template}"
HOOK_URL="${CLAUDE_HOOK_URL:-https://raw.githubusercontent.com/ippoan/claude-md/main/.claude/hooks/session-start-install-hooks.sh}"
SETTINGS_DEST="${CLAUDE_SETTINGS_DEST:-$CLAUDE_HOME/settings.json}"
HOOK_DEST="$CLAUDE_HOME/hooks/session-start-install-hooks.sh"
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

# --- 2. SessionStart hook script ---
if [ "${SKIP_HOOK:-0}" = "1" ]; then
  log "skip: SKIP_HOOK=1"
else
  mkdir -p "$(dirname "$HOOK_DEST")"
  curl -fsSL "$HOOK_URL" -o "$HOOK_DEST"
  chmod +x "$HOOK_DEST"
  log "hook: $HOOK_DEST (registered in settings.json template)"
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
