#!/bin/bash
# PreToolUse hook (matcher=mcp__github__create_pull_request): PR 作成直前に
# pr-chat-bridge skill (ippoan/claude-skills) を想起させる reminder を
# additionalContext で inject する。
#
# 動機: PR コメントを transport に CCoW ↔ Claude chat (Desktop/Cowork +
# Claude in Chrome) を連携させる pr-chat-bridge は「PR 作成の瞬間」に
# 想起されないと使われない (実装後に思い出しても依頼コメント・購読・
# draft/ready の判断が後手になる)。issue-write-reminder と同じ方式。
#
# 非強制: deny しない。ブラウザ検証が不要な PR (docs / CI / lib 等) では
# 無視してよい reminder として流す。
#
# 設計判断:
#   - pr-refs-link-guard.sh (deny する guard) とは役割を分ける
#   - additionalContext は ~500 chars 程度
#   - fail-open (python3 が無い env でも壊れない)
#
# env override:
#   CLAUDE_PR_CHAT_BRIDGE_SKIP=1   完全 skip (= dev/local 用)
#
# Refs ippoan/claude-md#100, ippoan/claude-skills#102
set -u

if [ "${CLAUDE_PR_CHAT_BRIDGE_SKIP:-0}" = "1" ]; then
  exit 0
fi

# python3 が無い env (ほぼ無いはずだが) は静かに skip
if ! command -v python3 >/dev/null 2>&1; then
  exit 0
fi

# stdin は読み捨てる (tool_input による分岐は後追いで拡張可能)
cat >/dev/null 2>&1 || true

emit() {
  python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":sys.argv[1]}}))' "$1" 2>/dev/null
}

read -r -d '' REMINDER <<'REMINDER_EOF' || true
[REMINDER — PR 作成時: ブラウザ検証の要否を判断]

この PR に UI / 画面変更が含まれ、実ブラウザでの動作確認が有益なら
**pr-chat-bridge skill** (ippoan/claude-skills) を検討:

1. チェックリスト付き検証依頼コメント (`<!-- pr-chat-bridge:request -->`) を投稿
2. user に chat 起動リンク (`https://claude.ai/new?q=<プロンプト>`) を提示
   → chat 側 Claude が Claude in Chrome で検証し結果をコメント
   → webhook でこのセッションが起床して処理
3. auto-merge との両立: **draft 型は preview 導入 repo 限定**
   (staging は draft で deploy されない)。それ以外は merge 後に
   linked issue + send_later self check-in で回収。

ブラウザ検証が不要な PR (docs / CI / lib 等) はこの reminder を無視してよい。
REMINDER_EOF

emit "$REMINDER"
exit 0
