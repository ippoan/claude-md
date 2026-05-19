#!/bin/bash
# Bootstrap script for Claude Code on the Web sessions.
#
# 5 段階で user-level セットアップを行う (各段階は env で個別 skip 可能):
#
#   1. ~/.claude/settings.json                          (claude-md の template, SessionStart + PreToolUse hook 登録済)
#   2. ~/.claude/CLAUDE.md                              (user-level memory に locale 指示を marker block で merge)
#   3. ~/.claude/hooks/*.sh                             (install-hooks / snapshot / drift / refresh-installer)
#   4. cc-relay shallow clone                           (ippoan/cc-relay)
#   5. cc-relay MCP server を user-level ~/.claude.json に登録
#      + (optional) github-mcp-admin entry を $GITHUB_MCP_ADMIN_TOKEN_JSON 経由で登録
#   6. ~/.claude/.install-stamp                         (検証用 epoch+ISO+version+hooks)
#   7. ~/.claude/.refresh-installer-marker              (refresh hook が使う sha)
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
#   CLAUDE_USER_MEMORY_URL   user-memory.md の URL (BASE_URL を上書き)
#   CLAUDE_USER_MEMORY_DEST  user-level CLAUDE.md の install 先 (default: $CLAUDE_HOME/CLAUDE.md)
#   CLAUDE_HOOK_URL          SessionStart hook script の URL (BASE_URL を上書き)
#   CLAUDE_HOME              ~/.claude の path (default: /root/.claude)
#   CLAUDE_SETTINGS_DEST     settings.json の install 先 (default: $CLAUDE_HOME/settings.json)
#   CLAUDE_JSON_DEST         ~/.claude.json の path (default: /root/.claude.json)
#   CC_RELAY_REPO            cc-relay の clone URL
#   CC_RELAY_DIR             cc-relay の clone 先 (default: /home/user/cc-relay, 無ければ $HOME/cc-relay)
#   CC_RELAY_MCP_URL         user-level に登録する cc-relay MCP server URL (default: prod)
#   GITHUB_MCP_URL_BASE      github-mcp-server-rs relay の base URL (default: https://mcp.ippoan.org)
#                            staging override: https://mcp-staging.ippoan.org
#   GITHUB_MCP_ADMIN_TOKEN_JSON
#                            github-mcp-server-rs `auth --scope mcp.admin` で焼いた
#                            token cache file (~/.config/github-mcp-server-rs/token-*.json) を
#                            CCoW env var に貼った値。set されると `github-mcp-admin` MCP entry
#                            を ~/.claude.json に追加し、Web セッションから branch protection
#                            tool (set/get/delete_branch_protection) を呼べるようにする。
#                            unset の場合は既存 cc-relay entry のみ登録 (graceful skip)。
#                            JSON 例: {"github_login":"alice","binding_jwt":"<JWT>",...}
#                            binding_jwt 以外の field は無視される (cache file 全体を貼り付け可)。
#   SKIP_SETTINGS=1          1 を立てると settings.json install を skip
#   SKIP_USER_MEMORY=1       1 を立てると ~/.claude/CLAUDE.md の locale block install を skip
#                            (global で英語応答にしたい時はこれを立てる)
#   SKIP_HOOK=1              1 を立てると SessionStart hook script の配置を skip
#   SKIP_CC_RELAY=1          1 を立てると cc-relay clone を skip
#   SKIP_MCP=1               1 を立てると MCP 登録を skip (cc-relay + github-mcp-admin 両方)
#   SKIP_GITHUB_MCP_ADMIN=1  1 を立てると GITHUB_MCP_ADMIN_TOKEN_JSON が set でも admin entry を skip
#   CLAUDE_INSTALL_STAMP     stamp ファイル path (default: $CLAUDE_HOME/.install-stamp)
#                            このファイルの mtime と中身で「今 session で install.sh が
#                            走ったか / cache 由来か」を即判定できる (fresh-env 検証用)
#   CLAUDE_MD_INSTALL_URL    session-start-refresh-installer.sh が fetch する
#                            install.sh URL (default: main raw)
#   CLAUDE_REFRESH_MARKER    refresh marker path
#                            (default: $CLAUDE_HOME/.refresh-installer-marker)
#   CLAUDE_REFRESH_TTL       refresh hook の network check skip TTL 秒 (default: 300)
set -eu

# Version stamp — rewritten on every push to main by
# .github/workflows/stamp-install-sh-version.yml. "dev" means "running from a
# branch / locally". CI replaces this with the commit SHA so the .install-stamp
# file lets fresh-env verification identify exactly which install.sh ran.
INSTALL_SH_VERSION="2026.05.16-163932-dde1d07"

CLAUDE_HOME="${CLAUDE_HOME:-/root/.claude}"
CLAUDE_MD_BASE_URL="${CLAUDE_MD_BASE_URL:-https://raw.githubusercontent.com/ippoan/claude-md/main}"
TEMPLATE_URL="${CLAUDE_MD_TEMPLATE_URL:-$CLAUDE_MD_BASE_URL/.claude/settings.json.template}"
SETTINGS_DEST="${CLAUDE_SETTINGS_DEST:-$CLAUDE_HOME/settings.json}"
USER_MEMORY_URL="${CLAUDE_USER_MEMORY_URL:-$CLAUDE_MD_BASE_URL/.claude/user-memory.md}"
USER_MEMORY_DEST="${CLAUDE_USER_MEMORY_DEST:-$CLAUDE_HOME/CLAUDE.md}"

# Hook scripts to install under $CLAUDE_HOME/hooks/. Add new entries here
# whenever settings.json.template registers another script. CLAUDE_HOOK_URL
# (legacy) can still override the first one for backwards compatibility.
HOOK_SCRIPTS=(
  "session-start-install-hooks.sh"
  "session-start-snapshot.sh"
  "pre-tool-claude-dir-drift.sh"
  "session-start-refresh-installer.sh"
)
LEGACY_HOOK_URL="${CLAUDE_HOOK_URL:-}"

# CI-managed: sha256 of each hook file in this repo at the time install.sh
# was generated. Rewritten by .github/workflows/stamp-install-sh-version.yml
# on every push to main that touches .claude/install.sh OR .claude/hooks/**.
#
# Why this exists: refresh-installer's drift detection compares the sha of
# install.sh itself. Without embedding hook content here, a hook-only change
# (e.g. claude-md PR #16 which only edited session-start-install-hooks.sh)
# leaves install.sh's sha unchanged → refresh-installer concludes "unchanged"
# → cached ~/.claude environments never pick up the new hook. Embedding the
# hook shas as data makes install.sh's sha a function of hook content, so
# any hook change triggers re-install via the existing sha compare.
#
# Format: "<name>=<sha256>", one per line, sorted by name.
HOOK_SHAS=$(cat <<'HOOK_SHAS_EOF'
pre-tool-claude-dir-drift.sh=bdf35f2dfb5dd360c320d84d9f8368dd585a90b4366aa30670c26e7087ccebd0
session-start-install-hooks.sh=cf6f1e7251ec34cba9f3d823ced5bcfd744a58377269ccc5a3c6c9d4ea9f2212
session-start-refresh-installer.sh=b81ad4f1e01af703be96a7d9881823e06804b46d085110bcaaf20ae3689658aa
session-start-snapshot.sh=42ccba0438c8e20fc064c88d2ca63a1c76cdc6c63189bfce4c2b8ebf02392afb
HOOK_SHAS_EOF
)

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
GITHUB_MCP_URL_BASE="${GITHUB_MCP_URL_BASE:-https://mcp.ippoan.org}"
GITHUB_MCP_ADMIN_TOKEN_JSON="${GITHUB_MCP_ADMIN_TOKEN_JSON:-}"

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

# --- 2. user-level CLAUDE.md (locale instruction in marker block) ---
# settings.json schema には locale / language に相当する key が無いので、
# 応答言語の default 化は user memory (~/.claude/CLAUDE.md) 経由で行う。
# marker block 方式 (BEGIN..END) で既存内容を保ったまま idempotent に merge する。
# project 側 ./CLAUDE.md (project memory) が user memory より優先されるので
# repo ごとの opt-out はそちらで上書きできる。
if [ "${SKIP_USER_MEMORY:-0}" = "1" ]; then
  log "skip: SKIP_USER_MEMORY=1"
else
  mkdir -p "$(dirname "$USER_MEMORY_DEST")"
  USER_MEMORY_TMP=$(mktemp)
  if curl -fsSL --max-time 15 "$USER_MEMORY_URL" -o "$USER_MEMORY_TMP"; then
    USER_MEMORY_DEST="$USER_MEMORY_DEST" USER_MEMORY_TMP="$USER_MEMORY_TMP" python3 - <<'PY'
import os, re

dest = os.environ["USER_MEMORY_DEST"]
src_path = os.environ["USER_MEMORY_TMP"]

BEGIN = "<!-- BEGIN claude-md user-memory:locale -->"
END = "<!-- END claude-md user-memory:locale -->"

with open(src_path) as f:
    template = f.read().strip()

block = f"{BEGIN}\n<!-- Managed by ippoan/claude-md install.sh. Edits inside this block are overwritten on the next session. -->\n{template}\n{END}"

try:
    with open(dest) as f:
        existing = f.read()
except FileNotFoundError:
    existing = ""

pat = re.compile(re.escape(BEGIN) + r".*?" + re.escape(END), re.DOTALL)
if pat.search(existing):
    new = pat.sub(block, existing, count=1)
else:
    sep = "" if not existing else ("\n" if existing.endswith("\n") else "\n\n")
    new = existing + sep + block + "\n"

if new != existing:
    tmp = dest + ".tmp"
    with open(tmp, "w") as f:
        f.write(new)
    os.replace(tmp, dest)
    print(f"[install.sh] user-memory: updated {dest} (locale block)")
else:
    print(f"[install.sh] user-memory: {dest} already up to date")
PY
    rm -f "$USER_MEMORY_TMP"
  else
    log "warn: user-memory fetch failed ($USER_MEMORY_URL); skipping"
    rm -f "$USER_MEMORY_TMP"
  fi
fi

# --- 3. Hook scripts (SessionStart + PreToolUse) ---
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

    # Defense in depth: verify downloaded content against CI-stamped sha.
    # raw.githubusercontent.com can serve stale cached content for ~5min
    # after a push, and the LEGACY_HOOK_URL override could point anywhere.
    # Mismatch is logged but does not abort install (best-effort recovery).
    expected_sha=$(printf '%s\n' "$HOOK_SHAS" | awk -F= -v n="$name" '$1==n{print $2; exit}')
    if [ -n "$expected_sha" ]; then
      actual_sha=$(sha256sum "$dest" 2>/dev/null | awk '{print $1}')
      if [ "$expected_sha" != "$actual_sha" ]; then
        log "warn: $name sha mismatch (expected ${expected_sha:0:12}, got ${actual_sha:0:12}) — CDN cache may be stale"
      fi
    fi

    log "hook: $dest"
  done
fi

# --- 4. cc-relay shallow clone ---
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

# --- 5. cc-relay MCP server + optional github-mcp-admin (user-level ~/.claude.json) ---
if [ "${SKIP_MCP:-0}" = "1" ]; then
  log "skip: SKIP_MCP=1"
else
  mkdir -p "$(dirname "$CLAUDE_JSON_DEST")"
  # admin entry is opt-in via env var; explicit SKIP override allowed.
  if [ "${SKIP_GITHUB_MCP_ADMIN:-0}" = "1" ]; then
    admin_token_for_py=""
  else
    admin_token_for_py="$GITHUB_MCP_ADMIN_TOKEN_JSON"
  fi
  GITHUB_MCP_ADMIN_TOKEN_JSON="$admin_token_for_py" \
  GITHUB_MCP_URL_BASE="$GITHUB_MCP_URL_BASE" \
  python3 - "$CLAUDE_JSON_DEST" "$CC_RELAY_MCP_URL" <<'PY'
import json, os, sys

path = sys.argv[1]
cc_relay_url = sys.argv[2]
admin_token_raw = os.environ.get("GITHUB_MCP_ADMIN_TOKEN_JSON", "")
admin_url_base = os.environ.get("GITHUB_MCP_URL_BASE", "https://mcp.ippoan.org").rstrip("/")

try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}

servers = data.setdefault("mcpServers", {})
servers["cc-relay"] = {"type": "http", "url": cc_relay_url}

admin_msg = None
if admin_token_raw:
    try:
        admin = json.loads(admin_token_raw)
        login = admin.get("github_login") or admin.get("login")
        jwt = admin.get("binding_jwt") or admin.get("access_token")
        if not login or not jwt:
            raise KeyError("github_login and binding_jwt (or access_token) required")
        servers["github-mcp-admin"] = {
            "type": "http",
            "url": f"{admin_url_base}/u/{login}/mcp",
            "headers": {"Authorization": f"Bearer {jwt}"},
        }
        admin_msg = f"registered github-mcp-admin ({admin_url_base}/u/{login}/mcp)"
    except (json.JSONDecodeError, KeyError, TypeError) as e:
        admin_msg = f"warn: GITHUB_MCP_ADMIN_TOKEN_JSON invalid ({e}); admin entry skipped"
        # leave any pre-existing admin entry alone in this error case — the user
        # can re-export and re-run, and we don't want to drop a working entry due
        # to a typo in a one-off override.
else:
    # idempotent cleanup: env var unset → drop any stale admin entry from a
    # previous session. CCoW envs are ephemeral but ~/.claude.json can survive
    # cache snapshots, so we want "unset env" to mean "no admin endpoint".
    if servers.pop("github-mcp-admin", None) is not None:
        admin_msg = "removed stale github-mcp-admin entry (GITHUB_MCP_ADMIN_TOKEN_JSON not set)"

tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
os.replace(tmp, path)
print(f"[install.sh] MCP: registered cc-relay ({cc_relay_url}) in {path}")
if admin_msg:
    print(f"[install.sh] MCP: {admin_msg}")
PY
fi

log "done"

# --- 6. Install stamp (always written last) ---
# fresh-env 検証用の epoch + ISO timestamp + script SHA + base URL を
# $CLAUDE_HOME/.install-stamp に書き出す。次の session で `cat` 1 発で
# 「setup script で install.sh が走ったか」「いつの版か」を即判定できる。
# CCoW env cache snapshot に焼き込まれた古い ~/.claude を踏むと
# このファイルが container 起動より大きく前の mtime を持つ (= cache 由来)。
STAMP_DEST="${CLAUDE_INSTALL_STAMP:-$CLAUDE_HOME/.install-stamp}"
STAMP_NOW_EPOCH=$(date +%s)
STAMP_NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
mkdir -p "$(dirname "$STAMP_DEST")"
cat > "$STAMP_DEST" <<STAMP
epoch=$STAMP_NOW_EPOCH
iso=$STAMP_NOW_ISO
base_url=$CLAUDE_MD_BASE_URL
install_sh_version=$INSTALL_SH_VERSION
hooks_installed=$([ "${SKIP_HOOK:-0}" = "1" ] && echo "skipped" || printf '%s,' "${HOOK_SCRIPTS[@]}" | sed 's/,$//')
STAMP
log "stamp: $STAMP_DEST ($STAMP_NOW_ISO, version=$INSTALL_SH_VERSION)"

# --- 7. Refresh marker (consumed by session-start-refresh-installer.sh) ---
# Record sha256 of *the same install.sh content that just ran* so the
# SessionStart refresh hook can detect when main has moved forward.
# Re-fetch from the URL because $0 is "bash" when curl|bash'd.
REFRESH_MARKER="${CLAUDE_REFRESH_MARKER:-$CLAUDE_HOME/.refresh-installer-marker}"
REFRESH_URL="${CLAUDE_MD_INSTALL_URL:-$CLAUDE_MD_BASE_URL/.claude/install.sh}"
self_sha=$(curl -fsSL --max-time 15 "$REFRESH_URL" 2>/dev/null | sha256sum 2>/dev/null | awk '{print $1}' || true)
if [ -n "${self_sha:-}" ]; then
  echo "$self_sha" > "$REFRESH_MARKER"
  log "refresh-marker: $REFRESH_MARKER (sha ${self_sha:0:12})"
fi
