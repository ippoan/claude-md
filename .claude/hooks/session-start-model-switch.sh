#!/bin/bash
# SessionStart hook: spawn_task (チップ) 起動の worktree セッションを
# `initialUserMessage: "/model <MODEL>"` で Opus に切り替える。
#
# 動機: Claude desktop (`CLAUDE_CODE_ENTRYPOINT=claude-desktop`) の spawn_task
# 起動セッションは **親セッションのモデルを継承**し、project / user どちらの
# `settings.json` の `model` も無視される (実測 2026-09-10, Refs #106 第 1 報)。
# 親を Fable (計画・レビュー役) にしていると、実装を任せた子まで Fable で走る。
# `CLAUDE_CODE_SUBAGENT_MODEL` は Agent tool のサブエージェント用で、
# spawn_task セッションには効かない。
#
# 唯一効いた経路が本 hook の `initialUserMessage` (Refs #106 第 2 報):
# 会話先頭に `/model <MODEL>` が local-command として入り、`PostModelSwitch` が
# `source=command` で発火する。**起動 prompt は置き換わらない** (子は `/model`
# の直後にチップの prompt を通常どおり受け取る)。切替は "this session only" で、
# settings は書き換わらない。
#
# 設計判断:
# - **worktree 判定は proxy にすぎない。** SessionStart payload に「spawn_task
#   起動か」を示す欄は無い (届くキーは session_id / transcript_path / cwd /
#   scratchpad_dir / hook_event_name / source のみ。`model` は来ない)。
#   チップ起動は必ず `/.claude/worktrees/` 配下なので cwd で代用しているが、
#   **親 (計画・レビュー役) が worktree 隔離で開かれると誤爆する**。
#   誤爆しても実害は小さく、人が `/model` で戻せる。まず入れて運用で様子を見る。
# - `source == "startup"` に限定する (resume / clear では流さない。既に人が
#   `/model` で選び直した session を上書きしないため)。
# - **desktop の画面表示は追随しない** (実測)。composer 右下は親のモデルのまま。
#   確認は transcript の `message.model` か `PostModelSwitch` の記録
#   (`post-model-switch-record.sh`) で行うこと。表示が古いタブでモデルセレクタを
#   触ると、アプリ側の値で set_model が飛んで戻る可能性がある。
# - `CLAUDE_SPAWN_MODEL` は allowlist `^[A-Za-z0-9._-]+$` に一致しなければ
#   **無出力で exit 0**。JSON 破壊と `initialUserMessage` への任意指示の注入を防ぐ
#   (この文字列はそのままユーザーターンとして Claude に届くため)。
# - fail-open: 条件外・python3 不在・payload 不正はすべて無出力で exit 0。
#
# opt-in: 本 hook は install.sh / settings.json.template には**登録されていない**。
# 使う人が自分の `~/.claude/settings.json` の `hooks.SessionStart` に足す
# (手順は README「モデルルーティング方針」節)。
#
# env override:
#   CLAUDE_SPAWN_MODEL        切り替え先モデル ID (default: claude-opus-4-8)
#   CLAUDE_SPAWN_MODEL_SKIP=1 完全 skip
set -u

if [ "${CLAUDE_SPAWN_MODEL_SKIP:-0}" = "1" ]; then
  exit 0
fi

MODEL="${CLAUDE_SPAWN_MODEL:-claude-opus-4-8}"

# allowlist: 英数字と . _ - のみ。空文字・それ以外を含む値は無出力で exit 0。
case "$MODEL" in
  '') exit 0 ;;
  *[!A-Za-z0-9._-]*) exit 0 ;;
esac

# python3 が無い env は静かに skip (JSON を手組みしない)
if ! command -v python3 >/dev/null 2>&1; then
  exit 0
fi

PAYLOAD="$(cat 2>/dev/null)" || exit 0

# payload から string field を 1 つ取り出す。parse 失敗・非 string は空文字。
read_field() {
  printf '%s' "$PAYLOAD" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
v = d.get(sys.argv[1]) if isinstance(d, dict) else None
if isinstance(v, str):
    print(v)
' "$1" 2>/dev/null
}

SOURCE="$(read_field source)"
CWD="$(read_field cwd)"

# spawn_task チップ起動の代理条件: 新規起動 + worktree 配下
[ "$SOURCE" = "startup" ] || exit 0
case "$CWD" in
  */.claude/worktrees/*) ;;
  *) exit 0 ;;
esac

python3 -c '
import json, sys
model = sys.argv[1]
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "initialUserMessage": "/model " + model,
    "additionalContext": "この session は SessionStart hook で " + model + " に切り替えた。desktop のモデル表示は追随しないので、確認は transcript の message.model か PostModelSwitch の記録で行うこと。",
}}))' "$MODEL" 2>/dev/null

exit 0
