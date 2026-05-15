#!/bin/bash
# PreToolUse hook (matcher=Bash): `git commit` を検知すると ~/.claude の
# session-start snapshot と現在の状態を比較し、drift があれば Claude に
# 非 blocking warning を additionalContext で注入する。
#
# 趣旨: 「~/.claude を session 中に弄ったまま session 終了 = 改変が container と
# 共に消失」する事故を防ぐ。drift があれば Claude が
#   - 意図的なら claude-md template repo に sync back
#   - 非意図的なら revert
# を判断できるようにする。
#
# 動作:
#   stdin から PreToolUse JSON を受け取る → tool_input.command を抽出 →
#   `git commit` を含まない場合は exit 0 で何もしない →
#   含む場合は snapshot と現状を比較し、差分があれば additionalContext を出力。
#
# exit code: 常に 0 (advisory; commit は block しない)。
# JSON 出力形式: PreToolUse の hookSpecificOutput.additionalContext。
#
# env override:
#   CLAUDE_HOME              ~/.claude の path (default: $HOME/.claude)
#   CLAUDE_DRIFT_SNAPSHOT    snapshot file path (default: $CLAUDE_HOME/.session-snapshot)
#   CLAUDE_DRIFT_MAX_FILES   warning に列挙する最大 file 数 (default: 10)
set -u

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
SNAP="${CLAUDE_DRIFT_SNAPSHOT:-$CLAUDE_HOME/.session-snapshot}"
MAX_FILES="${CLAUDE_DRIFT_MAX_FILES:-10}"

# Read tool input from stdin
input=$(cat 2>/dev/null || true)
cmd=$(printf '%s' "$input" | python3 -c 'import json,sys
try:
    d=json.loads(sys.stdin.read() or "{}")
    print(d.get("tool_input",{}).get("command",""))
except Exception:
    pass' 2>/dev/null || true)

# Match `git commit` as a standalone subcommand (avoid false positive on
# `git commit-tree`, `git --foo commit-graph`, paths containing "git commit", etc.)
case " $cmd " in
  *" git commit "*|*" git commit"|"git commit "*|"git commit") match=1 ;;
  *)
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:];&|])git[[:space:]]+commit([[:space:]]|$|-[mavF])'; then
      match=1
    else
      match=0
    fi
    ;;
esac
[ "$match" = "1" ] || exit 0

# No snapshot = first session run before snapshot hook landed. Stay silent.
[ -f "$SNAP" ] || exit 0

# Filter must match session-start-snapshot.sh exactly to avoid spurious diffs
# from harness runtime artifacts (Bash shell snapshots, harness backups, etc).
current=$(cd "$CLAUDE_HOME" 2>/dev/null && find . -type f \
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
  2>/dev/null | sort | xargs -r sha256sum 2>/dev/null)

if [ -z "$current" ]; then
  exit 0
fi

if printf '%s\n' "$current" | diff -q "$SNAP" - >/dev/null 2>&1; then
  exit 0
fi

# Build the changed-files list (added / modified / removed paths)
changed=$(diff "$SNAP" <(printf '%s\n' "$current") 2>/dev/null \
  | awk '/^[<>]/ {print $NF}' | sort -u | head -"$MAX_FILES")
[ -n "$changed" ] || exit 0

list=$(printf '%s' "$changed" | sed 's|^\./|  - |')
msg=$(printf '⚠️  ~/.claude/ drift detected since session start.

Modified/added/removed (relative to %s):
%s

This container is ephemeral — anything edited under ~/.claude/ outside the
claude-md template repo will be lost when the session ends.

If the change is intentional, sync it back to
https://github.com/ippoan/claude-md (~/.claude/sources/claude-md if cloned)
before committing in the current repo, so install.sh distributes it to
future fresh sessions.

If unintentional, revert before committing.' "$CLAUDE_HOME" "$list")

python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":sys.argv[1]}}))' "$msg"
exit 0
