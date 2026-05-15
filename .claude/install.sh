#!/bin/bash
# install user-level ~/.claude/settings.json from this repo's template.
#
# usage (CCoW environment Setup script 欄に 1 行貼る):
#   curl -fsSL https://raw.githubusercontent.com/ippoan/claude-md/main/.claude/install.sh | bash
#
# 直接叩いてもよい:
#   bash .claude/install.sh
set -eu

TEMPLATE_URL="${CLAUDE_MD_TEMPLATE_URL:-https://raw.githubusercontent.com/ippoan/claude-md/main/.claude/settings.json.template}"
DEST="${CLAUDE_SETTINGS_DEST:-/root/.claude/settings.json}"

mkdir -p "$(dirname "$DEST")"
curl -fsSL "$TEMPLATE_URL" -o "$DEST"

ALLOW_COUNT=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["permissions"]["allow"]))' "$DEST")
echo "installed: $DEST (allow=$ALLOW_COUNT)"
