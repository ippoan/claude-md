#!/bin/bash
# SessionStart hook: ~/.claude の baseline snapshot を取る。
# 後段の pre-tool-claude-dir-drift.sh が `git commit` 前にこれと比較し、
# session 中に発生した drift を Claude に warning として通知する。
#
# 対象: ~/.claude 配下の text 系設定ファイル (json/sh/md/toml)。
# 除外: harness が runtime に作る noise (projects/ sources/ cache/ tool-results/
# shell-snapshots/ backups/ sessions/ session-env/ shell-snapshots/) + snapshot
# 自身 + marker。drift hook 側 (pre-tool-claude-dir-drift.sh) の filter と
# 完全一致させること。
# 出力: $SNAP に "<sha256>  <relative-path>" 行を sort して保存。
#
# 出力 (Claude への通知): JSON で hookSpecificOutput.additionalContext を返す
# (session-start-install-hooks.sh と同形式)。
#
# env override:
#   CLAUDE_HOME              ~/.claude の path (default: $HOME/.claude)
#   CLAUDE_DRIFT_SNAPSHOT    snapshot file path (default: $CLAUDE_HOME/.session-snapshot)
set -u

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
SNAP="${CLAUDE_DRIFT_SNAPSHOT:-$CLAUDE_HOME/.session-snapshot}"

emit() {
  python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.argv[1]}}))' "$1"
}

if [ ! -d "$CLAUDE_HOME" ]; then
  emit "drift-snapshot: $CLAUDE_HOME not found — skipped"
  exit 0
fi

# Use cd + relative paths so the snapshot is portable across CLAUDE_HOME values.
# Filter must match pre-tool-claude-dir-drift.sh exactly to avoid spurious diffs.
count=$(cd "$CLAUDE_HOME" && find . -type f \
  \( -name '*.json' -o -name '*.sh' -o -name '*.md' -o -name '*.toml' \) \
  -not -path './projects/*' \
  -not -path './sources/*' \
  -not -path './cache/*' \
  -not -path './tool-results/*' \
  -not -path './shell-snapshots/*' \
  -not -path './backups/*' \
  -not -path './sessions/*' \
  -not -path './session-env/*' \
  -not -name '.session-snapshot' \
  -not -name '.install-hooks-marker' \
  -not -name '.install-stamp' \
  -not -name '.last-cleanup' \
  2>/dev/null | sort | xargs -r sha256sum 2>/dev/null | tee "$SNAP" | wc -l)

emit "drift-snapshot: baseline captured ($count files) -> $SNAP"
