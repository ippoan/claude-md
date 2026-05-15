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

## Bootstrap script (`.claude/install.sh`)

Claude Code on the Web の session を立ち上げた直後の user-level セットアップを 1 本に集約した bootstrap script。Setup script 欄 (推奨) または session 冒頭 paste のいずれも下記 1 行で済む:

```sh
curl -fsSL https://raw.githubusercontent.com/ippoan/claude-md/main/.claude/install.sh | bash
```

### 何が走るか

| 段階 | 内容 | skip env |
|---|---|---|
| 1. **settings.json** | `.claude/settings.json.template` を `~/.claude/settings.json` に install (allow list 55 件 + SessionStart hook 登録) | `SKIP_SETTINGS=1` |
| 2. **SessionStart hook 配置** | `.claude/hooks/session-start-install-hooks.sh` を `~/.claude/hooks/` に配置。**毎 session** で CCoW per-session git proxy 経由で yhonda-ohishi/claude-skills + claude-hooks を `~/.claude/sources/` に sync + skill symlink (詳細は次節) | `SKIP_HOOK=1` |
| 3. **cc-relay clone** | `ippoan/cc-relay` を shallow clone (`--depth 1`)。既存 `.git` があれば skip。`/home/user` がある環境 (CCoW) はそこへ、無ければ `$HOME/cc-relay` | `SKIP_CC_RELAY=1` |
| 4. **cc-relay MCP server 登録** | `~/.claude.json` の `mcpServers["cc-relay"]` に `https://mcp.ippoan.org/mcp` (prod) を merge。既存 key は保持 | `SKIP_MCP=1` |

`set -eu` で 1〜2 は失敗時 Setup script を fail させる (curl から claude-md 自身を取れない時点で先に進めても無意味)。3〜4 は accessibility 失敗時に warn だけ出して継続。

### SessionStart hook (`session-start-install-hooks.sh`)

claude-skills / claude-hooks を取得する処理を **SessionStart hook に分離した理由**:

- Setup script 時点では attached repo が clone される前なので、CCoW の git proxy URL (`http://local_proxy@127.0.0.1:<port>/git/…`) を discover できない
- raw.githubusercontent.com を anonymous で叩いても private repo (yhonda-ohishi/*) は 404 になる
- SessionStart hook なら毎 session attached repo の `.git/config` から proxy URL を抜き出せる。そして CCoW の scoped credential が yhonda-ohishi/* にも valid

hook 内部処理:

1. `/home/user/*/` を走査して `.git/config` から `http://local_proxy@127.0.0.1:<port>/git` 部分を抽出
2. その proxy URL を base に `git clone --depth 1 …/yhonda-ohishi/{claude-skills,claude-hooks}` を `~/.claude/sources/` に展開 (既存なら `fetch --depth 1 + reset --hard`)
3. `~/.claude/sources/claude-skills/<name>/SKILL.md` を `~/.claude/skills/<name>` に symlink (既存の非 symlink = user 手書きは触らない)
4. TTL (`CLAUDE_HOOKS_INSTALL_TTL`, default 3600s) 内は network sync を skip。symlink 更新だけ実施
5. proxy URL を見つけられない / clone 失敗時は fail-open (additionalContext にエラー記録、session は継続)

PAT も INTERNAL_SHARED_SECRET も CCoW env vars 追加も不要。CCoW の network allowlist にも変更不要 (127.0.0.1 のみ叩く)。

### env override

| 変数 | 既定値 | 用途 |
|---|---|---|
| `CLAUDE_MD_BASE_URL` | `https://raw.githubusercontent.com/ippoan/claude-md/main` | claude-md raw base URL。**branch 切替の単一窓口** (PR テスト用) |
| `CLAUDE_MD_TEMPLATE_URL` | `$CLAUDE_MD_BASE_URL/.claude/settings.json.template` | settings.json template の URL (個別上書き) |
| `CLAUDE_HOOK_URL` | `$CLAUDE_MD_BASE_URL/.claude/hooks/session-start-install-hooks.sh` | SessionStart hook script の URL (個別上書き) |
| `CLAUDE_HOME` | `/root/.claude` | `.claude` dir |
| `CLAUDE_SETTINGS_DEST` | `$CLAUDE_HOME/settings.json` | settings.json install 先 |
| `CLAUDE_JSON_DEST` | `/root/.claude.json` | MCP 登録先 |
| `CC_RELAY_REPO` | `https://github.com/ippoan/cc-relay.git` | cc-relay clone URL |
| `CC_RELAY_DIR` | `/home/user/cc-relay` (CCoW) / `$HOME/cc-relay` | cc-relay clone 先 |
| `CC_RELAY_MCP_URL` | `https://mcp.ippoan.org/mcp` (prod) | user-level MCP server URL。staging 切替: `https://mcp-staging.ippoan.org/mcp` |
| `SKIP_SETTINGS` / `SKIP_HOOK` / `SKIP_CC_RELAY` / `SKIP_MCP` | unset | `1` で各段階 skip |
| `CLAUDE_HOOKS_INSTALL_TTL` | `3600` | hook 側: network sync を skip する TTL (秒) |
| `CLAUDE_HOOKS_SCAN_DIRS` | `/home/user` | hook 側: attached repo を探す親 dir |

### 運用

- **A. session 冒頭で 1 回 paste** — 1 行 (上記) を冒頭 prompt に貼り付け。書き込み直後の tool call から runtime が新 allow list を読む (= 即時反映)。
- **B. CCoW environment の Setup script に登録 (推奨)** — Environment → Setup script 欄に同じ 1 行を貼ると container 起動時に 1 回走る。毎 session の paste 不要。詳細は https://code.claude.com/docs/en/claude-code-on-the-web 。

### A/B 共通

- 各段階で `[install.sh] …` プレフィクス付きでログを出すので、Setup script ログ / session の最初の Bash 結果で成否を確認できる。
- SessionStart hook の結果は session 起動時の hook log (additionalContext) で確認できる: `install-hooks: synced via proxy (skills=28) ok` 等
- project-level `.claude/settings.json` (repo の中に commit する形) と併用可能。重複は project 側が勝つ。

## Tool 使用許可テンプレート (`.claude/settings.json.template`)

bootstrap の段階 1 で install される user-level template。`~/.claude/settings.json` に置けば repo attach に関係なく effective になる (= cross-repo の cc-relay / auth-worker / claude-hooks 系セッションで permission prompt を減らせる)。

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
