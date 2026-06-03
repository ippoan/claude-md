#!/bin/bash
# SessionStart hook: claude-md CLAUDE.md.template から派生する **strict policy**
# を additionalContext で毎 session Claude に inject する。
#
# 動機: 同じ rule を CLAUDE.md.template (project memory) と user memory 両方に
# 書いても Claude が reflex 行動で違反する事例が頻発した (例: PR を作るたびに
# `mcp__github__enable_pr_auto_merge` を user 指示無しで呼ぶ →
# CLAUDE.md.template §「Claude による auto-merge enable は禁止」違反、実害は
# ippoan/secrets-inventory-gcp#21 等の "CI green 前に merge" 事故)。
#
# project memory / user memory は **conversation の前段** に置かれるため、
# 長い session では context summarization で薄れる。本 hook は session 開始時
# に必ず Claude の context に injection されるため、毎回 fresh に reminder を
# 渡せる。
#
# 設計判断:
# - 毎回出す reminder は **絶対に守るべき rule** に絞る (= reminder fatigue
#   防止)。general guidance は CLAUDE.md.template / project CLAUDE.md に残す
# - hint は「やってはいけないこと」+「やるべき代替手段」の形で書く
# - additionalContext は ~500 chars 程度に抑え、Claude の context budget を
#   無駄に食わない
# - fail-open: jq / python3 が無い env でも壊れない (graceful skip)
#
# env override:
#   CLAUDE_POLICY_REMINDER_SKIP=1   完全 skip (= dev/local 用)
set -u

if [ "${CLAUDE_POLICY_REMINDER_SKIP:-0}" = "1" ]; then
  exit 0
fi

emit() {
  python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.argv[1]}}))' "$1" 2>/dev/null
}

# python3 が無い env (ほぼ無いはずだが) は静かに skip
if ! command -v python3 >/dev/null 2>&1; then
  exit 0
fi

# policy 本体。Claude.md.template の最も誤違反されやすい rule を絞り込む。
# 改行は \n で区切り、additionalContext は単一 string として渡る。
read -r -d '' POLICY <<'POLICY_EOF' || true
[STRICT POLICY — claude-md template, hook-enforced reminder]

これらは過去に実害を出した reflex 違反です。守ること:

1. **PR 作成直後に `mcp__github__enable_pr_auto_merge` を呼ばない。**
   user が「auto-merge enable して」と明示指示した時だけ呼ぶ。
   理由: branch protection / required check 不揃いの repo で「現時点で satisfied」と
   判定され CI green 前に merge される事故が複数発生 (ippoan/secrets-inventory-gcp#21,
   ippoan/ci-dashboard#89)。auto-merge.yml workflow を持つ repo は workflow 側で
   後から enable する設計。
   推奨: PR 作成 → `subscribe_pr_activity` で CI 待ち → user 判断で merge。

2. **PR description / commit message に `Closes #N` / `Fixes #N` / `Resolves #N` を書かない。**
   `Refs #N` / `Related to #N` / `Part of #N` を使う。
   理由: auto-merge が走った瞬間 issue が auto-close され、release tag 時の手動
   close 確認 UI と整合しない。

3. **`mcp__github__create_or_update_file` / `push_files` を使わない (permissions.deny 済)。**
   /home/user/<repo> の pre-clone で `git add / commit / push` する。
   理由: file 全文を JSON param で送ると ~30× token 消費 (実害: secrets-inventory-gcp#23 で
   ~100KB / 25K token 浪費)。

4. **秘密の値 (API key / token / shared secret) を LLM context・plain env・tool-call param に載せない。**
   `secret-inject` skill を使う:
   `openssl rand -hex 32 | bash ~/.claude/skills/secret-inject/scripts/inject-secret.sh NAME --targets gcp,github`
   値は shell→curl(--data-binary)→worker→Secret Manager だけを通り、context/log/response を一切経由しない。
   - `create_secret` / `rotate_secret` MCP tool は value を param に載せる = **禁止** (= 値が会話に残る)。
   - 自分で `openssl rand | cat` して値を読む / Cloud Run の plain env `value:` に直書きするのも禁止。
     Cloud Run は **secretKeyRef** (Secret Manager 参照) で渡す。
   理由: 値が会話/log に出た時点で compromised → 全数 rotate が必要。実害多数 (本 reminder の追加契機)。

これらは reminder。違反したら user が即指摘するので、その時に修正で OK。
POLICY_EOF

emit "$POLICY"
exit 0
