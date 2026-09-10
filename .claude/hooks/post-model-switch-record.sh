#!/bin/bash
# PostModelSwitch hook: モデル切替を 1 行ログに追記するだけ。出力なし。
#
# 動機: Claude desktop の画面表示 (composer 右下) は CLI 内部のモデル切替を
# 拾わない (実測 2026-09-10, Refs #106 補足)。`session-start-model-switch.sh` が
# `/model` を流しても表示は親のモデルのままなので、**本当に切り替わったかを
# 後から確かめる手段**が要る。transcript の `message.model` を読む代わりに、
# 切替イベントそのものを 1 行ずつ落としておく。
#
# 記録先: ~/.claude/state/model-switch.log (追記のみ)
#   <ISO8601>\t<session_id>\t<from_model> -> <to_model>\trequested=<requested_model>\tsource=<source>
#
# 設計判断:
# - **stdout に何も出さない。** PostModelSwitch の応答を Claude の context に
#   足す価値が無く、hook 出力の JSON 形式を気にする必要も無くなる。
# - payload には context_tokens / prompt_cache_warm / pricing なども届くが、
#   記録するのは 4 フィールドだけ (grep しやすさ優先、値は増えたら追う)。
# - fail-open: python3 不在・payload 不正・書き込み失敗はすべて exit 0。
#
# opt-in: install.sh / settings.json.template には**登録されていない**。
# 使う人が自分の `~/.claude/settings.json` の `hooks.PostModelSwitch` に足す
# (手順は README「モデルルーティング方針」節)。
#
# env override:
#   CLAUDE_HOME                ~/.claude の path (default: $HOME/.claude)
#   CLAUDE_MODEL_SWITCH_LOG    ログ file path (default: $CLAUDE_HOME/state/model-switch.log)
#   CLAUDE_MODEL_SWITCH_RECORD_SKIP=1  完全 skip
set -u

if [ "${CLAUDE_MODEL_SWITCH_RECORD_SKIP:-0}" = "1" ]; then
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  exit 0
fi

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
LOG="${CLAUDE_MODEL_SWITCH_LOG:-$CLAUDE_HOME/state/model-switch.log}"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || exit 0

python3 -c '
import datetime, json, sys

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if not isinstance(d, dict):
    sys.exit(0)

def f(key):
    v = d.get(key)
    return v if isinstance(v, str) and v else "?"

line = "\t".join([
    datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
    f("session_id"),
    f("from_model") + " -> " + f("to_model"),
    "requested=" + f("requested_model"),
    "source=" + f("source"),
])
try:
    with open(sys.argv[1], "a", encoding="utf-8") as fh:
        fh.write(line + "\n")
except Exception:
    sys.exit(0)
' "$LOG" 2>/dev/null

exit 0
