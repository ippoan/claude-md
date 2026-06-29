#!/bin/bash
# PreToolUse hook (matcher=mcp__github__issue_write): issue create/update 直前に
# 必ず守るべき rule を additionalContext で inject する。
#
# 動機: SessionStart の policy-reminder と同じ意図 — long session で context
# summarization に薄まる前に reminder を fresh に流し込む。issue 作成時の
# よくある reflex 違反:
#   - 完了条件 (Acceptance Criteria) セクションを書き忘れる
#   - 計画長文を issue 本文に丸ごと埋め込む (本来は docs/plan-*.md に PR で起こすべき)
#   - `Closes #N` を本文に書く (auto-close 連鎖トリガになる)
#   - title prefix の統一忘れ
#
# 設計判断:
#   - SessionStart policy-reminder と同様、絶対に守るべき rule に絞る
#   - additionalContext は ~500 chars 程度
#   - fail-open (jq / python3 が無い env でも壊れない)
#
# env override:
#   CLAUDE_ISSUE_REMINDER_SKIP=1   完全 skip (= dev/local 用)
set -u

if [ "${CLAUDE_ISSUE_REMINDER_SKIP:-0}" = "1" ]; then
  exit 0
fi

# python3 が無い env (ほぼ無いはずだが) は静かに skip
if ! command -v python3 >/dev/null 2>&1; then
  exit 0
fi

# stdin は無視してよい (method=create/update どちらでも同じ reminder を出す)。
# tool_input を見て分岐したい場合は後追いで拡張可能。
cat >/dev/null 2>&1 || true

emit() {
  python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":sys.argv[1]}}))' "$1" 2>/dev/null
}

read -r -d '' REMINDER <<'REMINDER_EOF' || true
[STRICT POLICY — issue create/update, hook-enforced reminder]

issue を作成/更新する前に確認:

1. **「完了条件 (Acceptance Criteria)」セクションを含める。**
   CLAUDE.md.template 規約:「各 issue の『完了条件』セクションが done の定義」
   実装/検証/運用/切替判定を checklist (- [ ]) 形式で。done の客観基準が無い
   issue は merge 判定できない。

2. **計画 (plan / design) を issue 本文に長文で埋め込まない。**
   CLAUDE.md.template 規約:
   > 計画は会話や issue 本文の口頭で済ませず、repo 内ファイル
   > (例: docs/plan-<topic>.md) として起こし、その追加・更新を PR レビューに
   > 乗せて履歴を残す。
   issue は「親 issue / リンクのハブ」、SoT は repo 内 markdown。
   長文計画を書きたくなったら **plan doc を PR で追加**する選択肢を user に提案する。

3. **`Closes #N` / `Fixes #N` / `Resolves #N` を本文に書かない。**
   `Refs #N` / `Related to #N` / `Part of #N` を使う。
   auto-close が release 時の手動 close 確認 UI と整合しない。

4. **タイトル prefix を統一する。**
   `[調査]` (investigation) / `[計画]` (planning) / `[バグ]` (bug) /
   `[infra]` 等で grep 可能に。

これらは reminder。違反したら user が即指摘するので、その時に修正で OK。
REMINDER_EOF

emit "$REMINDER"
exit 0
