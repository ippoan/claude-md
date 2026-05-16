# CLAUDE.md

このリポジトリは Claude Code on the Web (CCoW) 向けの **user-level bootstrap (`install.sh` + SessionStart/PreToolUse hooks)** と、5 つの consumer repo (`ippoan/{cc-relay,auth-worker,ci-dashboard}`, `yhonda-ohishi/{claude-hooks,claude-skills}`) 用の **`CLAUDE.md` 共通テンプレート** を配布する。

詳細仕様は [`README.md`](./README.md) を読む。ここには Claude が編集作業の前に押さえておくべきものだけを書く。

## まず読むもの

- [`README.md`](./README.md) — 利用者向け full reference (install.sh 段階、hook 仕様、env override 表、settings.json template 由来)
- [`.claude/install.sh`](./.claude/install.sh) — bootstrap 本体 (Setup script から curl される)
- [`.claude/hooks/`](./.claude/hooks/) — install.sh が `~/.claude/hooks/` に配置する hook scripts 本体
- [`.claude/settings.json.template`](./.claude/settings.json.template) — install.sh が `~/.claude/settings.json` に展開する template
- [`.github/workflows/stamp-install-sh-version.yml`](./.github/workflows/stamp-install-sh-version.yml) — install.sh の `INSTALL_SH_VERSION` と `HOOK_SHAS` を main push の度に自動 rewrite する CI

## ブランチ運用

- 編集は `claude/<topic>` ブランチで行い、PR 経由で main へ merge する
- main 直 push 禁止。stamp workflow が main に直 push する commit (`INSTALL_SH_VERSION` と `HOOK_SHAS` の rewrite) のみ例外
- branch 命名は他の ippoan repo と同じ規約: `claude/<short-desc>` または `<issue-number>-<type>-<short-description>`

## 編集時に必ず守ること

### `.claude/install.sh` を編集する

- 直接 sha 操作する必要は無い。`INSTALL_SH_VERSION="dev"` と `HOOK_SHAS=...` ブロックは [`stamp-install-sh-version.yml`](./.github/workflows/stamp-install-sh-version.yml) が main 上で書き換える
- `HOOK_SCRIPTS=(...)` 配列に hook を追加した場合、`HOOK_SHAS=` ブロックにも同じ name の行を追加 (sha は dummy で良い、workflow が main で実値に rewrite する)
- `settings.json.template` の `hooks.<event>` 登録も忘れずに追加 (hook scripts 配置と template への登録は 1 セット)

### `.claude/hooks/*.sh` を編集する

- shebang は `#!/bin/bash`、`set -u` を入れる (refresh-installer は `set -eu`)
- hook 出力は SessionStart の場合 `{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "..."}}` の JSON 1 オブジェクト。複数行表示したい場合は additionalContext の値に改行文字を入れる (各 hook の `emit()` ヘルパが python3 で json.dumps する)
- 失敗時は fail-open (additionalContext に warning 出して exit 0)。session 自体は止めない
- network は CCoW git proxy (`http://local_proxy@127.0.0.1:<port>/git`) を attached repo の `.git/config` から discover する。raw.githubusercontent.com への直 fetch は anonymous で公開 repo のみ可

### hook-only 変更が既存 CCoW env に届く流れ

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

### `~/.claude/settings.json` と `~/.claude.json` の変更は 1 session 遅延

Claude Code は session 起動時に `~/.claude/settings.json` と `~/.claude.json` を読んでメモリに hold する。refresh hook が disk を書き換えても **当該 session には反映されない**。

| 変更 | 反映 |
|---|---|
| `permissions.allow/deny/ask` 追加 | 次 session |
| `hooks.<event>` 追加(新規 hook 登録) | 次 session |
| `~/.claude.json` `mcpServers` 追加 | 次 session |
| 既存 `hooks/*.sh` の中身修正 | 即時 (hook 発火時に disk read) |
| skills / sources / cc-relay clone の更新 | 即時 |

即時反映が必要な場合のみ、CCoW Setup script 欄に `# bust YYYYMMDD-HHMMSS` を追加して保存 → 次 session で新 install.sh を走らせる。

## ビルド / テスト / lint

このリポジトリは shell + markdown + workflow yaml だけなので、専用の test command は無い。代わりに以下を手元 (or session) で叩く:

```sh
# install.sh の syntax check
bash -n .claude/install.sh

# hook scripts の syntax check
bash -n .claude/hooks/*.sh

# install.sh を実際に走らせる (dry-run 相当の skip env を全部立てれば外部副作用 0)
SKIP_SETTINGS=1 SKIP_HOOK=1 SKIP_CC_RELAY=1 SKIP_MCP=1 bash .claude/install.sh
```

CI で実行されているのは:

- [`stamp-install-sh-version.yml`](./.github/workflows/stamp-install-sh-version.yml) — main push 時に `INSTALL_SH_VERSION` と `HOOK_SHAS` を rewrite。**PR では走らない** ので feature branch の install.sh は古い sha のまま (= refresh-installer は merge 後初めて反応する)

## GitHub 自動化

- PR template 無し
- Branch protection 無し (workflow が main 直 push する都合)
- Required status checks 無し
- `Refs #N` vs `Closes #N` — auto-close は使わない (release 時に手動 close)

## やってはいけないこと

- `.claude/install.sh` の `INSTALL_SH_VERSION` や `HOOK_SHAS=` を手動で書き換えない (workflow と衝突する)
- hook 出力の JSON 形式を崩さない (Claude Code harness が parse 失敗すると hook 全体が無視される)
- `~/.claude/settings.json.template` の `hooks` を編集する時は対応する `.claude/hooks/<name>.sh` を必ず同 PR で追加 (install.sh の `HOOK_SCRIPTS=` 配列にも追加)
- refresh-installer の TTL を 60 秒未満にしない (毎 session network burst になる)
- force push、main 直 push (stamp workflow 以外)、secret commit
