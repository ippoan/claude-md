---
name: claude-md-map
generated-from: claude-md:230702674ffbbb41934ff7d04fac66d2bf5d3f2b
paths: [.claude/]
description: ippoan/claude-md (CCoW 向け user-level bootstrap install.sh + hooks) の編集詳細マップ。`.claude/install.sh` や `.claude/hooks/*.sh` を編集する前に読む。hook-only 変更が既存 CCoW env に届く伝播フロー (stamp workflow → HOOK_SHAS rewrite → refresh-installer)、`~/.claude/settings.json` / `~/.claude.json` の変更が反映されるまで 1 session 遅延する表、install.sh/hooks 編集時の詳細規約をまとめる。トリガー:「install.sh 編集」「hook 追加」「HOOK_SHAS」「HOOK_SCRIPTS」「refresh-installer」「hook が反映されない」「settings.json 反映遅延」「session-start-install-hooks」「stamp-install-sh-version」「claude-md-map」等。
---

# claude-md-map — ippoan/claude-md 編集詳細マップ

CLAUDE.md 骨格から移設した詳細セクション。編集規約の要点 (何を守るべきか) は
CLAUDE.md 本体の「編集時に必ず守ること」「やってはいけないこと」を見る。ここには
その背景にある詳しい手順・表・フローを置く。

## `.claude/install.sh` を編集する

- 直接 sha 操作する必要は無い。`INSTALL_SH_VERSION="dev"` と `HOOK_SHAS=...` ブロックは [`stamp-install-sh-version.yml`](../../../.github/workflows/stamp-install-sh-version.yml) が main 上で書き換える
- `HOOK_SCRIPTS=(...)` 配列に hook を追加した場合、`HOOK_SHAS=` ブロックにも同じ name の行を追加 (sha は dummy で良い、workflow が main で実値に rewrite する)
- `settings.json.template` の `hooks.<event>` 登録も忘れずに追加 (hook scripts 配置と template への登録は 1 セット)

## `.claude/user-memory.md` を編集する

- org 全 repo 共通の作業規範 (issue→PR→push / lib-first / secrets / **Local-first
  testing (#102)** 等) のセクション集。install.sh が毎 session `~/.claude/CLAUDE.md`
  に配布する — 追記は次 session から全 repo に効く。
- **圧縮したまま保つ** (CLAUDE.md ダイエット #90)。詳細レシピは claude-skills 側の
  skill (例: `local-first-testing`) に置き、user-memory からは名前で参照する。

## `.claude/hooks/*.sh` を編集する

- shebang は `#!/bin/bash`、`set -u` を入れる (refresh-installer は `set -eu`)
- hook 出力は SessionStart の場合 `{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "..."}}` の JSON 1 オブジェクト。複数行表示したい場合は additionalContext の値に改行文字を入れる (各 hook の `emit()` ヘルパが python3 で json.dumps する)
- 失敗時は fail-open (additionalContext に warning 出して exit 0)。session 自体は止めない
- network は CCoW git proxy (`http://local_proxy@127.0.0.1:<port>/git`) を attached repo の `.git/config` から discover する。raw.githubusercontent.com への直 fetch は anonymous で公開 repo のみ可

## hook-only 変更が既存 CCoW env に届く流れ

`session-start-install-hooks.sh` だけを編集する PR (例: PR #18 — key-skills ✓/✗ 出力追加) を例に追う:

1. PR が main へ merge される
2. GitHub Actions `stamp-install-sh-version.yml` が起動
3. workflow は変更された hook の新 sha256 を計算
4. install.sh 内の `HOOK_SHAS=...` ブロックの該当行をその新 sha に書き換えて main へ自動 push
5. **install.sh 自体の sha も書き換えに伴って変わる** ← PR #17 で導入された肝
6. 既存 CCoW env で次の session が始まる時、`session-start-refresh-installer.sh` が:
   - `CLAUDE_MD_INSTALL_URL` から新 install.sh を fetch
   - sha を計算 → `.refresh-installer-marker` の sha と違う → 再実行
   - install.sh が curl で新 hook を `~/.claude/hooks/` に上書き配置
   - marker を新 sha で更新
7. 同じ session 内ですぐ `install-hooks` hook が新版で走る (hook ファイルは hook 発火時に disk から再 read されるため即時)

PR #17 以前は (4) の HOOK_SHAS 機構が無く、hook ファイルだけ変えても install.sh の中身は不変 → sha も不変 → refresh-installer は「変わっていない」と判定 → 既存 env は古い hook を使い続ける、というリグレッションがあった。

## `~/.claude/settings.json` と `~/.claude.json` の変更は 1 session 遅延

Claude Code は session 起動時に `~/.claude/settings.json` と `~/.claude.json` を読んでメモリに hold する。refresh hook が disk を書き換えても **当該 session には反映されない**。

| 変更 | 反映 |
|---|---|
| `permissions.allow/deny/ask` 追加 | 次 session |
| `hooks.<event>` 追加(新規 hook 登録) | 次 session |
| `~/.claude.json` `mcpServers` 追加 | 次 session |
| 既存 `hooks/*.sh` の中身修正 | 即時 (hook 発火時に disk read) |
| skills / sources / cc-relay clone の更新 | 即時 |

即時反映が必要な場合のみ、CCoW Setup script 欄に `# bust YYYYMMDD-HHMMSS` を追加して保存 → 次 session で新 install.sh を走らせる。
