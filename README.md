# claude-md

Claude Code 向け `CLAUDE.md` の共通テンプレート。

`ippoan/{cc-relay,auth-worker,ci-dashboard}` および `yhonda-ohishi/{claude-hooks,claude-skills}` 5 つの repo の `CLAUDE.md` を読み比べた結果、半分以上は同じセクション構造で書かれていることが分かった。本 repo はその共通部分を 1 つの template に集約し、各 repo の `CLAUDE.md` を再生成可能な形にする。

## このリポジトリの構成

```
.
├── README.md              ← (これ)
├── CLAUDE.md.template     ← 全 repo 共通の base template
└── variants/
    ├── rust-workspace.md      ← Rust workspace 向け差分 (cc-relay)
    └── cloudflare-worker.md   ← Cloudflare Workers 向け差分 (auth-worker)
```

実 repo の `CLAUDE.md` は consumer 側 (cc-relay/auth-worker/...) の `main`
にコミットされているものが正 — 本 repo には reference 用の examples を置か
ない (drift する一方なので)。比較したい場合は consumer repo の git history
を辿ること。

## 共通セクション (`CLAUDE.md.template`)

5 repo を比較して以下 7 セクションが共通項として抽出された。順序は固定推奨:

| # | セクション | どう書くか |
|---|---|---|
| 1 | 冒頭タイトル + 1 行 intro | `# CLAUDE.md` + repo の存在意義を 1 文 |
| 2 | **まず読むもの** | 新規 contributor が 5 分で全体像を掴めるリンク集 (README / ARCHITECTURE / docs/ / Project board) |
| 3 | **ブランチ運用 / Worktree** | branch 命名規則、worktree の使い分け、`main` 直 push 禁止 |
| 4 | **ビルド / テスト / lint** | PR 出す前に手元で叩く command 一覧 (CI と同じものを並べる) |
| 5 | **Hooks** | `.claude/settings.json` から呼ぶ hook の有無、versioning 方針、`yhonda-ohishi/claude-hooks` への依存 |
| 6 | **GitHub 自動化** | auto-merge yml、Branch protection の Required status checks、PR template、`Refs #N` vs `Closes #N` |
| 7 | **やってはいけないこと** | force push、直 push、secret commit、未検証 macOS/Win 対応コード追加 等 |

各 repo 固有のセクションは template の **末尾** に置く (ex: cc-relay の sub-agent workflow、auth-worker の publish flow、claude-hooks の hook 一覧表)。

## Variants

repo 種別に応じて template の §4 (ビルド/テスト/lint) と §6 (自動化) だけ差し替えると 90% カバーできる:

| variant | 当てはまる repo | 主な差分 |
|---|---|---|
| `variants/rust-workspace.md` | cc-relay | `cargo fmt/clippy/test --workspace`、`PROTOCOL_VERSION` bump、release `Cargo.toml workspace.package.version` の同期 |
| `variants/cloudflare-worker.md` | auth-worker | `npm test` / `npm run typecheck`、`wrangler deploy` は CI 経由、`*.vue` の strict type 注釈 |

claude-hooks / claude-skills / ci-dashboard は base template + 末尾固有セクションで足りる (variant 不要)。

## 使い方

新規 repo に `CLAUDE.md` を作る:

```sh
# 1. base を持ってくる
curl -fsSL https://raw.githubusercontent.com/ippoan/claude-md/main/CLAUDE.md.template > CLAUDE.md

# 2. 該当 variant の差分を §4/§6 に貼り替え
curl -fsSL https://raw.githubusercontent.com/ippoan/claude-md/main/variants/rust-workspace.md

# 3. `<<...>>` プレースホルダを実値に置換
sed -i 's|<<REPO_NAME>>|cc-relay|g' CLAUDE.md
# ... 以下同様
```

プレースホルダ一覧:

| プレースホルダ | 例 |
|---|---|
| `<<REPO_NAME>>` | `cc-relay` |
| `<<REPO_PURPOSE_ONELINER>>` | "GitHub Issue を broker にした agent 間メッセージ relay" |
| `<<KEY_DOCS>>` | `ARCHITECTURE.md` / `docs/credentials.md` |
| `<<PROJECT_BOARD_URL>>` | `https://github.com/orgs/ippoan/projects/7` |
| `<<BRANCH_NAMING_PATTERN>>` | `<issue-number>-<type>-<short-description>` or `claude/<topic>` |
| `<<BUILD_CMDS>>` | `cargo fmt --all -- --check` 等のブロック |
| `<<REQUIRED_STATUS_CHECKS>>` | `rust (fmt)` / `rust (clippy)` / `rust (test)` |
| `<<DOMAIN_SPECIFIC_SECTIONS>>` | repo 固有の節 (sub-agent workflow 等) |

## 再生成検証

既存 5 repo の `CLAUDE.md` を template から再生成して diff が空であることを CI
で検証する仕組みは未実装 (issue 化 予定)。当面は consumer repo 側 PR レビュー
で「template の対応セクションと矛盾していないか」を手目視確認する。

## Tool 使用許可テンプレート (`.claude/settings.json.template`)

Claude Code on Web の session で頻出するツール許可を 1 枚に集約した user-level template。
`~/.claude/settings.json` に置けば repo attach に関係なく effective になる (= cross-repo の cc-relay / auth-worker / claude-hooks 系セッションで permission prompt を減らせる)。

### install

2 通りの運用がある。**B が推奨** (毎 session 何もしなくて良い)。

#### A. session 冒頭で 1 回 paste

```sh
curl -fsSL https://raw.githubusercontent.com/ippoan/claude-md/main/.claude/settings.json.template \
  -o ~/.claude/settings.json
```

- Claude Code on Web の container は ephemeral なので、新 session ごとに上記 one-liner を冒頭 prompt に貼り付ける運用。
- 書き込み直後の tool call から runtime が新 allow list を読む (= 即時反映)。

#### B. CCoW environment の Setup script に登録 (推奨)

Claude Code on the Web の environment 設定には **Setup script** 欄があり、
container 起動時に 1 回だけ実行される。ここに以下を貼っておけば fresh
container ごとに自動で `~/.claude/settings.json` が install され、毎 session
の paste 作業は不要になる。

```sh
#!/bin/bash
set -eu
mkdir -p /root/.claude
curl -fsSL https://raw.githubusercontent.com/ippoan/claude-md/main/.claude/settings.json.template \
  -o /root/.claude/settings.json
```

- CCoW の container は `root` で動くので home は `/root` (≒ `~`)。`~` 展開を避けて絶対パスで書いておくと setup script 実行時のシェル差異に左右されない。
- template 側を更新した場合、次に新規 container が立ち上がる session から自動で取り込まれる (既存 session には影響しない)。
- 設定場所: Claude Code on the Web の Environment → Setup script 欄。詳細は https://code.claude.com/docs/en/claude-code-on-the-web 。

#### A/B 共通

- project-level `.claude/settings.json` (repo の中に commit する形) と併用可能。重複は project 側が勝つ。
- 検証: 適用後 `python3 -c 'import json; print(len(json.load(open("/root/.claude/settings.json"))["permissions"]["allow"]))'` で allow list の件数を確認できる (現 template は 55 件)。

### 中身 (要旨)

| 区分 | 例 |
|---|---|
| built-in tool | `Read` / `Edit` / `Write` / `Skill` / `ToolSearch` / `AskUserQuestion` |
| Bash read-only | `ls:*` / `cat:*` / `head:*` / `tail:*` / `grep:*` / `find:*` / `pwd` / `which:*` / `env` / `env:*` |
| Bash safe-write | `mkdir:*` / `chmod:*` / `cp:*` / `mv:*` / `ln:*` / `echo:*` |
| Bash dev | `python3:*` / `curl:*` / `bash:*` / `ss:*` |
| git | `git status/log/diff/branch/fetch/pull/push/add/commit/checkout/switch/rev-parse/ls-remote/config --get:*` |
| GitHub MCP read | `mcp__github__{issue,pull_request}_read` / `*_file_contents` / `list_{releases,branches,commits,pull_requests,issues,...}` / `search_*` |
| GitHub MCP write (低リスク) | `mcp__github__add_issue_comment` |
| PR subscribe | `mcp__github__{subscribe,unsubscribe}_pr_activity` |

**入れていないもの** (per-PR で都度承認したい): `merge_pull_request` / `create_pull_request` / `push_files` / `delete_file` / `create_repository` / `fork_repository` / `add_comment_to_pending_review` / 一般 Bash の `rm:*` / `git reset --hard` 等の破壊系。

### derivation

本 template の allow list は [ippoan/cc-relay#37](https://github.com/ippoan/cc-relay/issues/37) の Phase F acceptance session ([cse_…6bEte](https://github.com/ippoan/cc-relay/issues/37#issuecomment-4456995515)) で実際に叩いた tool から派生。新しい tool を追加する場合は同 issue にリンクして PR を切る。

## 関連

- 検証セッションのきっかけ: [ippoan/cc-relay#37](https://github.com/ippoan/cc-relay/issues/37) Phase F 検証中に「5 repo の CLAUDE.md 揺らぎが大きすぎる」と判明
- 参照元 repo: `ippoan/{cc-relay,auth-worker,ci-dashboard}`、`yhonda-ohishi/{claude-hooks,claude-skills}`
