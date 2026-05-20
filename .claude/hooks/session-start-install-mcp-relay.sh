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
#   /home/claude/.claude/remote/.oauth_token  Anthropic OAT
#                                   (issue ippoan/auth-worker#174 経由)
#
# どれも無い場合は graceful skip (additionalContext で skipped と通知)。
#
# OAT-based binding (issue #174):
#   CCoW container には Anthropic OAT (sk-ant-oat01-...) が常駐する。本 hook は
#   auth-worker `/mcp/pair/grant-via-oat` を OAT で叩いて binding_jwt を取得し、
#   `~/.config/<binary>/token-<env>.json` に hydrate する (= 既存 install-mcp.sh
#   の token cache path に焼く)。grant-via-oat が 404 (= OAT が未 bind) を返した
#   場合は additionalContext で Claude に register orchestration を要請する
#   (mcp__github__add_issue_comment + curl register endpoint)。
#
# env override:
#   CLAUDE_HOOKS_MCP_RELAY_BRANCH   ippoan/mcp-relay-rs の branch
#                                   (default: main)
#   SKIP_INSTALL_MCP_RELAY=1        この hook 全体を skip
#   GITHUB_MCP_PIN_TAG              install-mcp.sh に forward
#   REF_FILES_MCP_PIN_TAG           install-mcp-ref-files.sh に forward
#   GITHUB_MCP_ENV / REF_FILES_MCP_ENV  staging|prod (default: staging)
#   AUTH_WORKER_ORIGIN              grant-via-oat を叩く auth-worker origin
#                                   (default: https://auth-staging.ippoan.org)
#   SKIP_OAT_BINDING=1              OAT-based hydrate を skip (legacy path のみ)
#   OAT_BINDING_TRACKING_REPO       register endpoint で使う issue 投稿先 repo
#                                   (default: ippoan/auth-worker)
#   OAT_BINDING_TRACKING_ISSUE      register endpoint で使う issue 番号
#                                   (default: 174)
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

ENV_NAME_GITHUB="${GITHUB_MCP_ENV:-staging}"
ENV_NAME_REF_FILES="${REF_FILES_MCP_ENV:-staging}"
TOKEN_CACHE_GITHUB="${HOME}/.config/github-mcp-server-rs/token-${ENV_NAME_GITHUB}.json"
TOKEN_CACHE_REF_FILES="${HOME}/.config/ref-files-mcp-server-rs/token-${ENV_NAME_REF_FILES}.json"

# ─── OAT-based silent bootstrap (issue ippoan/auth-worker#174) ────────────
#
# fresh container では env も browser session も無いが、Anthropic OAT が
# `/home/claude/.claude/remote/.oauth_token` に常駐するため、auth-worker の
# `/mcp/pair/grant-via-oat` を叩けば KV bind 済みなら 1 発で binding_jwt が
# 取れる。未 bind なら additionalContext で Claude に register flow を委ねる。
OAT_FILE="/home/claude/.claude/remote/.oauth_token"
AUTH_ORIGIN="${AUTH_WORKER_ORIGIN:-https://auth-staging.ippoan.org}"
TRACK_REPO="${OAT_BINDING_TRACKING_REPO:-ippoan/auth-worker}"
TRACK_ISSUE="${OAT_BINDING_TRACKING_ISSUE:-174}"

oat_msg=""
oat_grant_login=""
need_register=0
oat_hash=""
nonce=""

if [ "${SKIP_OAT_BINDING:-0}" != "1" ] && [ -r "$OAT_FILE" ]; then
  oat=$(tr -d '[:space:]' < "$OAT_FILE")
  if [ -n "$oat" ]; then
    oat_hash=$(printf '%s' "$oat" | sha256sum | awk '{print $1}')
    # Try grant-via-oat for each aud. Skip when token cache file already exists
    # (idempotent — pre-staged token JSON env / previous session の cache を尊重)。
    grant_one() {
      local aud="$1" cache="$2" label="$3"
      if [ -s "$cache" ]; then
        # 既存 cache から github_login を読んで downstream に伝える
        # (install.sh が OAT path で焼いた直後 hook が走るケース、または
        # 前 session の cache が container に残っているケース)。これが無いと
        # GITHUB_LOGIN unset 判定で hook が skip emit してしまう。
        local login
        login=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("github_login",""))' "$cache" 2>/dev/null || echo "")
        if [ -n "$login" ] && [ -z "$oat_grant_login" ]; then
          oat_grant_login="$login"
        fi
        oat_msg="$oat_msg ${label}:cache-exists"
        return 0
      fi
      local tmp resp
      tmp=$(mktemp)
      resp=$(curl -sS -o "$tmp" -w "%{http_code}" --max-time 10 \
        -X POST "${AUTH_ORIGIN}/mcp/pair/grant-via-oat" \
        -H "Authorization: Bearer $oat" \
        -H "Content-Type: application/json" \
        -d "{\"aud\":\"${aud}\",\"scope\":\"mcp.read mcp.write\"}" \
        2>/dev/null || echo "000")
      case "$resp" in
        200)
          mkdir -p "$(dirname "$cache")"
          cp "$tmp" "$cache"
          chmod 600 "$cache"
          local login
          login=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("github_login",""))' "$cache" 2>/dev/null || echo "")
          if [ -n "$login" ]; then
            oat_grant_login="$login"
          fi
          oat_msg="$oat_msg ${label}:200"
          ;;
        404)
          need_register=1
          oat_msg="$oat_msg ${label}:404"
          ;;
        000)
          oat_msg="$oat_msg ${label}:network-fail"
          ;;
        *)
          oat_msg="$oat_msg ${label}:http=$resp"
          ;;
      esac
      rm -f "$tmp"
    }
    grant_one "github-mcp-server-rs" "$TOKEN_CACHE_GITHUB" "github"
    grant_one "ref-files-mcp-server-rs" "$TOKEN_CACHE_REF_FILES" "ref-files"

    if [ "$need_register" = "1" ]; then
      # nonce: 16 hex chars from /dev/urandom (= 64-bit, sufficient against
      # accidental collision on a single tracking issue).
      nonce=$(head -c 8 /dev/urandom | xxd -p)
    fi
  fi
fi

# install-mcp.sh は GITHUB_LOGIN が必要 (pair URL 構築 + token cache 不在時の
# pair flow 用)。grant-via-oat が解決したら export して downstream に渡す。
if [ -z "${GITHUB_LOGIN:-}" ] && [ -n "$oat_grant_login" ]; then
  export GITHUB_LOGIN="$oat_grant_login"
fi

# Need either GITHUB_LOGIN, hydrated token cache JSON env, or existing token
# cache file on disk. Otherwise install-mcp.sh would fail on missing login.
if [ -z "${GITHUB_LOGIN:-}" ] \
  && [ ! -f "$TOKEN_CACHE_GITHUB" ] \
  && [ ! -f "$TOKEN_CACHE_REF_FILES" ] \
  && [ -z "${GITHUB_MCP_TOKEN_JSON:-}" ] \
  && [ -z "${REF_FILES_MCP_TOKEN_JSON:-}" ]; then
  if [ "$need_register" = "1" ]; then
    # OAT は読めたが KV bind されていない → Claude に register orchestration を要請。
    register_url="${AUTH_ORIGIN}/mcp/pair/register-via-github-comment"
    ctx="install-mcp-relay: OAT bound に未 register。次の手順で binding を完了させてください:

  1. mcp__github__add_issue_comment で tracking issue にコメント投稿:
       owner: $(echo "$TRACK_REPO" | cut -d/ -f1)
       repo:  $(echo "$TRACK_REPO" | cut -d/ -f2-)
       issue_number: $TRACK_ISSUE
       body:  \"oat-binding: $oat_hash $nonce\"
     → response から comment id を取得 (例: comment.id=123456)

  2. 取得した comment id で auth-worker register endpoint を叩く
     (Bearer OAT を付けると issue #176 の org_uuid binding も同時に作成され、
      次 fresh container は新 OAT でも silent bootstrap される — 推奨):
       curl -sS -X POST '$register_url' \\
         -H \"Authorization: Bearer \$(cat /home/claude/.claude/remote/.oauth_token)\" \\
         -H 'Content-Type: application/json' \\
         -d '{\"comment_url\":\"https://api.github.com/repos/$TRACK_REPO/issues/comments/<id>\",\"oat_hash\":\"$oat_hash\",\"nonce\":\"$nonce\"}'
     → 200 { github_login, bound: true, org_uuid_bound: true } を期待

  3. 再度 grant-via-oat を叩いて binding_jwt を取得・token cache に焼く:
       for aud in github-mcp-server-rs ref-files-mcp-server-rs; do
         case \"\$aud\" in
           github-mcp-server-rs) cache=\"\$HOME/.config/github-mcp-server-rs/token-${ENV_NAME_GITHUB}.json\" ;;
           ref-files-mcp-server-rs) cache=\"\$HOME/.config/ref-files-mcp-server-rs/token-${ENV_NAME_REF_FILES}.json\" ;;
         esac
         mkdir -p \"\$(dirname \"\$cache\")\"
         curl -sS -X POST '${AUTH_ORIGIN}/mcp/pair/grant-via-oat' \\
           -H \"Authorization: Bearer \$(cat /home/claude/.claude/remote/.oauth_token)\" \\
           -H 'Content-Type: application/json' \\
           -d \"{\\\"aud\\\":\\\"\$aud\\\",\\\"scope\\\":\\\"mcp.read mcp.write\\\"}\" \\
           -o \"\$cache\"
         chmod 600 \"\$cache\"
       done

  4. (本 session の bridge を立てたい場合) 上記完了後に install-mcp(-ref-files).sh を再実行:
       curl -sSfL https://raw.githubusercontent.com/ippoan/mcp-relay-rs/main/.claude/hooks/install-mcp.sh | bash
       curl -sSfL https://raw.githubusercontent.com/ippoan/mcp-relay-rs/main/.claude/hooks/install-mcp-ref-files.sh | bash

  以降 fresh container でも grant-via-oat 即 200 で silent bootstrap される (30d KV TTL)。
  status: ${oat_msg:-(none)}"
    emit "$ctx"
    exit 0
  fi
  # diagnostic: なぜ skip path に来たか分かるよう各 input の有無を出す
  diag=""
  [ -f "$TOKEN_CACHE_GITHUB" ] && diag="${diag} github-cache=present" || diag="${diag} github-cache=absent"
  [ -f "$TOKEN_CACHE_REF_FILES" ] && diag="${diag} ref-files-cache=present" || diag="${diag} ref-files-cache=absent"
  [ -r "$OAT_FILE" ] && diag="${diag} oat=readable" || diag="${diag} oat=absent"
  emit "install-mcp-relay: GITHUB_LOGIN and token caches all unset — skipped${oat_msg} [${diag# }]"
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

emit "install-mcp-relay: github=$status_github ref-files=$status_ref_files (branch=$BRANCH)${oat_msg}${pair_msg}"
