#!/bin/bash
# SessionStart hook: bring up ippoan/mcp-relay-rs binaries
# (github-mcp-server-rs + ref-files-mcp-server-rs) as WebSocket bridges
# to mcp(-staging).ippoan.org.
#
# Both binaries attach to the same McpSession DO (per github_login) via
# the auth-worker's Option C multiplex (PR #167) — Hello frame で binary
# が自分の `service` を申告し、DO は per-service WS attachment を保持して
# tools/list を aggregate する。これにより 1 registered MCP URL で
# github (40 tools) + ref-files (9 tools) の混在 tool set が見える。
#
# 本 hook は **WS bridge の起動だけ** を担う。MCP URL を ~/.claude.json
# mcpServers に register するのは install.sh が CCoW Setup script 段階で
# 行う (cc-relay / github-mcp-admin と同じ枠組み)。
#
# 上流 install-mcp(-ref-files).sh は STATE_DIR を別ディレクトリで持つよう
# 直っている (ippoan/mcp-relay-rs#15 で fix):
#   github   → $CLAUDE_PROJECT_DIR/.claude/mcp-state
#   ref-files → $CLAUDE_PROJECT_DIR/.claude/mcp-state-ref-files
#
# 必要条件 (どれか満たせば bridge が立つ):
#   GITHUB_LOGIN                    CCoW Setup-script secret
#                                   (initial pair flow を駆動する claim_login)
#   GITHUB_MCP_TOKEN_JSON           hydrated token cache (silent bootstrap)
#   REF_FILES_MCP_TOKEN_JSON        同上 (ref-files 側)
#   既に焼けた token cache file が
#   ~/.config/{github,ref-files}-mcp-server-rs/token-*.json に存在
#
# どれも無い場合は graceful skip (additionalContext で skipped と通知)。
#
# env override:
#   CLAUDE_HOOKS_MCP_RELAY_BRANCH   ippoan/mcp-relay-rs の branch
#                                   (default: main)
#   SKIP_INSTALL_MCP_RELAY=1        この hook 全体を skip
#   GITHUB_MCP_PIN_TAG              install-mcp.sh に forward
#   REF_FILES_MCP_PIN_TAG           install-mcp-ref-files.sh に forward
#   GITHUB_MCP_ENV / REF_FILES_MCP_ENV  staging|prod (default: staging)
#
# 出力: SessionStart hook spec の JSON 1 行 (additionalContext)
set -u

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"

emit() {
  python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.argv[1]}}))' "$1"
}

# Only run inside Claude Code on the Web — local sessions have no use for
# the WS bridge.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

if [ "${SKIP_INSTALL_MCP_RELAY:-0}" = "1" ]; then
  emit "install-mcp-relay: SKIP_INSTALL_MCP_RELAY=1 — skipped"
  exit 0
fi

# Need either GITHUB_LOGIN, hydrated token cache JSON env, or existing token
# cache file on disk. Otherwise install-mcp.sh would fail on missing login.
ENV_NAME_GITHUB="${GITHUB_MCP_ENV:-staging}"
ENV_NAME_REF_FILES="${REF_FILES_MCP_ENV:-staging}"
TOKEN_CACHE_GITHUB="${HOME}/.config/github-mcp-server-rs/token-${ENV_NAME_GITHUB}.json"
TOKEN_CACHE_REF_FILES="${HOME}/.config/ref-files-mcp-server-rs/token-${ENV_NAME_REF_FILES}.json"

if [ -z "${GITHUB_LOGIN:-}" ] \
  && [ ! -f "$TOKEN_CACHE_GITHUB" ] \
  && [ ! -f "$TOKEN_CACHE_REF_FILES" ] \
  && [ -z "${GITHUB_MCP_TOKEN_JSON:-}" ] \
  && [ -z "${REF_FILES_MCP_TOKEN_JSON:-}" ]; then
  emit "install-mcp-relay: GITHUB_LOGIN and token caches all unset — skipped"
  exit 0
fi

BRANCH="${CLAUDE_HOOKS_MCP_RELAY_BRANCH:-main}"
BASE="https://raw.githubusercontent.com/ippoan/mcp-relay-rs/${BRANCH}/.claude/hooks"

# Fire github-mcp-server-rs installer (state-dir: mcp-state).
status_github="ok"
if ! curl -sSfL "$BASE/install-mcp.sh" 2>/dev/null | bash >/dev/null 2>&1; then
  status_github="fail"
fi

# Fire ref-files-mcp-server-rs installer (state-dir: mcp-state-ref-files).
status_ref_files="ok"
if ! curl -sSfL "$BASE/install-mcp-ref-files.sh" 2>/dev/null | bash >/dev/null 2>&1; then
  status_ref_files="fail"
fi

# Surface pair URLs if either binary is still in pair mode (token cache
# absent) so the user can 1-click approve from the additionalContext.
project_dir="${CLAUDE_PROJECT_DIR:-}"
pair_msg=""
if [ -n "$project_dir" ]; then
  for sd in "mcp-state" "mcp-state-ref-files"; do
    log="$project_dir/.claude/$sd/pair.log"
    [ -f "$log" ] || continue
    # Only show if WS upgrade not yet ack-ed (= pair still pending).
    if grep -q "WS upgrade accepted" "$log" 2>/dev/null; then continue; fi
    url=$(grep -oE 'https://[^[:space:]]+/mcp/pair/[A-Za-z0-9_-]{30,60}' "$log" 2>/dev/null | head -1)
    [ -n "$url" ] && pair_msg="$pair_msg [click: $url]"
  done
fi

emit "install-mcp-relay: github=$status_github ref-files=$status_ref_files (branch=$BRANCH)$pair_msg"
