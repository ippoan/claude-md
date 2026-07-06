# CLAUDE.md

CCoW 向け user-level bootstrap (`install.sh` + hooks) と、5 consumer repo
(`ippoan/{cc-relay,auth-worker,ci-dashboard,claude-hooks,claude-skills}`) 用の
`CLAUDE.md` 共通テンプレートを配布する。詳細は [`README.md`](./README.md)。
編集手順の詳細・hook 伝播フロー・settings 反映遅延表は `claude-md-map` skill を参照。

## まず読むもの

- [`.claude/install.sh`](./.claude/install.sh) — bootstrap 本体
- [`.claude/hooks/`](./.claude/hooks/) — install.sh が配置する hook scripts 本体
- [`.claude/settings.json.template`](./.claude/settings.json.template) — settings.json 展開元
- [`.claude/user-memory.md`](./.claude/user-memory.md) — locale 指示の merge 元
- [`.github/workflows/stamp-install-sh-version.yml`](./.github/workflows/stamp-install-sh-version.yml) — `INSTALL_SH_VERSION`/`HOOK_SHAS` 自動 rewrite CI

## ブランチ運用

- 編集は `claude/<topic>` ブランチで PR 経由 main へ
- main 直 push 禁止。stamp workflow の自動 push commit のみ例外
- branch 命名: `claude/<short-desc>` または `<issue-number>-<type>-<short-description>`

## 編集時に必ず守ること

- `.claude/install.sh`: `HOOK_SCRIPTS=` に hook を追加したら `HOOK_SHAS=` にも同名の行を追加する
- `.claude/hooks/*.sh`: shebang `#!/bin/bash` + `set -u`、SessionStart hook 出力は JSON 1 オブジェクト厳守、失敗時は fail-open (exit 0)

## ビルド / テスト / lint

```sh
bash -n .claude/install.sh
bash -n .claude/hooks/*.sh
SKIP_SETTINGS=1 SKIP_HOOK=1 SKIP_CC_RELAY=1 SKIP_MCP=1 bash .claude/install.sh
```

`stamp-install-sh-version.yml` は main push でのみ走る (PR では走らない)。

## GitHub 自動化

- PR template 無し / Branch protection 無し / Required status checks 無し
- `Refs #N` を使う (`Closes/Fixes/Resolves` は使わない。release 時に手動 close)

## やってはいけないこと

- `.claude/install.sh` の `INSTALL_SH_VERSION` や `HOOK_SHAS=` を手動で書き換えない (workflow と衝突する)
- hook 出力の JSON 形式を崩さない (Claude Code harness が parse 失敗すると hook 全体が無視される)
- `~/.claude/settings.json.template` の `hooks` を編集する時は対応する `.claude/hooks/<name>.sh` を必ず同 PR で追加 (install.sh の `HOOK_SCRIPTS=` 配列にも追加)
- refresh-installer の TTL を 60 秒未満にしない (毎 session network burst になる)
- force push、main 直 push (stamp workflow 以外)、secret commit
