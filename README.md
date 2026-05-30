# claude-md

Claude Code 向け `CLAUDE.md` の共通テンプレート。

`ippoan/{cc-relay,auth-worker,ci-dashboard,claude-hooks,claude-skills}` 5 つの repo の `CLAUDE.md` を読み比べた結果、半分以上は同じセクション構造で書かれていることが分かった。本 repo はその共通部分を 1 つの template に集約し、各 repo の `CLAUDE.md` を再生成可能な形にする。

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
| 5 | **Hooks** | `.claude/settings.json` から呼ぶ hook の有無、versioning 方針、`ippoan/claude-hooks` への依存 |
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

Claude Code on the Web の session を立ち上げた直後の user-level セットアップを 1 本に集約した bootstrap script。

### Setup script に貼る URL (1 回だけ paste、以降編集しない)

```sh
curl -fsSL https://raw.githubusercontent.com/ippoan/claude-md/main/.claude/install.sh | bash
```

main の最新を fetch。`SessionStart` hook の `session-start-refresh-installer.sh` が **毎 session 起動時** に同じ URL から install.sh を再 fetch し、disk 上 sha と diff があれば再 run する。hooks / install.sh logic / skills / cc-relay clone の更新は **Setup script 欄を一切触らずに自動で配布される**。

**ただし 1 session 遅延する例外**:

- `~/.claude/settings.json` の `permissions` 追加・hook 登録の追加
- `~/.claude.json` の `mcpServers` 追加

Claude Code が起動時に 1 度だけ read してメモリに hold するため、これらの変更は **次 session から有効**。即時反映したい場合のみ Setup script 欄を bust:

```sh
# bust 20260515-093000   ← 数字を変えてから保存
curl -fsSL https://raw.githubusercontent.com/ippoan/claude-md/main/.claude/install.sh | bash
```

CI workflow `.github/workflows/stamp-install-sh-version.yml` が main への push のたびに `INSTALL_SH_VERSION` を `YYYY.MM.DD-HHMMSS-<short-SHA>` に書き換えるので、`~/.claude/.install-stamp` を `cat` すれば deploy 済 version が即わかる。

### 参考

- [Claude Code on the web — Setup script cache 仕様](https://code.claude.com/docs/en/claude-code-on-the-web#environment-caching) — 公式 docs
- [`anthropics/claude-code` #30737](https://github.com/anthropics/claude-code/issues/30737) — Allow reloading permissions/settings in a running session
- [`anthropics/claude-code` #5513](https://github.com/anthropics/claude-code/issues/5513) — `/reloadSettings` command feature request

### 何が走るか

| 段階 | 内容 | skip env |
|---|---|---|
| 1. **settings.json** | `.claude/settings.json.template` を `~/.claude/settings.json` に install (allow list 65 件 + SessionStart 3 hook + PreToolUse 1 hook + PostToolUse 1 hook 登録 + `locale: "ja"` + `LANG/LC_ALL` env) | `SKIP_SETTINGS=1` |
| 2. **user-memory CLAUDE.md** | `.claude/user-memory.md` を取得して `~/.claude/CLAUDE.md` に marker block (`<!-- BEGIN claude-md user-memory:locale -->` … `<!-- END … -->`) として idempotent に merge。block 外の手書き内容は保持。応答言語を日本語 default にする ([#26](https://github.com/ippoan/claude-md/issues/26)) | `SKIP_USER_MEMORY=1` |
| 3. **hook scripts 配置** | `.claude/hooks/*.sh` を `~/.claude/hooks/` に 4 本配置: `session-start-install-hooks.sh` (毎 session で skills/hooks を proxy 経由 sync) + `session-start-snapshot.sh` (`~/.claude` baseline 作成) + `pre-tool-claude-dir-drift.sh` (`git commit` 時の drift 警告) + `session-start-refresh-installer.sh` (main の install.sh を fetch して差分があれば再 run、Setup script 編集不要にする) | `SKIP_HOOK=1` |
| 4. **cc-relay clone** | `ippoan/cc-relay` を shallow clone (`--depth 1`)。既存 `.git` があれば skip。`/home/user` がある環境 (CCoW) はそこへ、無ければ `$HOME/cc-relay` | `SKIP_CC_RELAY=1` |
| 5. **cc-relay MCP server 登録** | `~/.claude.json` の `mcpServers["cc-relay"]` に `https://mcp.ippoan.org/mcp` (prod) を merge。既存 key は保持。OAT がある環境では併せて `github-mcp-server-rs` / `ref-files-mcp-server-rs` (mcp-relay) と `secrets-inventory` (read-only、`grant-via-oat` で mint した `binding_jwt` を静的 `Authorization` header に焼く、Refs [ippoan/secrets-inventory#61](https://github.com/ippoan/secrets-inventory/issues/61)) も登録 | `SKIP_MCP=1` (個別: `SKIP_SECRETS_INVENTORY_MCP=1`) |

`set -eu` で 1 は失敗時 Setup script を fail させる (curl から claude-md 自身を取れない時点で先に進めても無意味)。2 (user-memory) は fetch 失敗時に warn だけ出して継続 (locale block 無くても session は動く)。3〜5 も accessibility 失敗時は warn のみ。

### SessionStart hook (`session-start-install-hooks.sh`)

claude-skills / claude-hooks を取得する処理を **SessionStart hook に分離した理由**:

- Setup script 時点では attached repo が clone される前なので、CCoW の git proxy URL (`http://local_proxy@127.0.0.1:<port>/git/…`) を discover できない
- raw.githubusercontent.com を anonymous で叩いても private repo (ippoan/*) は 404 になる
- SessionStart hook なら毎 session attached repo の `.git/config` から proxy URL を抜き出せる。そして CCoW の scoped credential が ippoan/* にも valid

hook 内部処理:

1. `/home/user/*/` を走査して `.git/config` から `http://local_proxy@127.0.0.1:<port>/git` 部分を抽出
2. その proxy URL を base に `git clone --depth 1 …/ippoan/claude-skills + ippoan/claude-hooks` を `~/.claude/sources/` に展開 (既存なら `fetch --depth 1 + reset --hard`)
3. `~/.claude/sources/claude-skills/<name>/SKILL.md` を `~/.claude/skills/<name>` に symlink (既存の非 symlink = user 手書きは触らない)
4. TTL (`CLAUDE_HOOKS_INSTALL_TTL`, default 3600s) 内は network sync を skip。symlink 更新だけ実施
5. proxy URL を見つけられない / clone 失敗時は fail-open (additionalContext にエラー記録、session は継続)
6. **key-skills 検査**: `CLAUDE_HOOKS_KEY_SKILLS` (default `"skill-creator open-multirepo"`) の各 skill について `$SKILLS_DIR/<name>/SKILL.md` の有無を ✓/✗ で additionalContext に出力。✗ がある時は `← / menu reload needed` を付ける (= / メニューを開く前に「今出てる状態か」を判定できる)

PAT も INTERNAL_SHARED_SECRET も CCoW env vars 追加も不要。CCoW の network allowlist にも変更不要 (127.0.0.1 のみ叩く)。

### Auto-refresh hook (`session-start-refresh-installer.sh`)

**Setup script は 1 回 paste したら以降編集不要** を実現する hook。毎 session 起動時に `$CLAUDE_MD_INSTALL_URL` (default: main raw URL) から install.sh を fetch、sha256 を `~/.claude/.refresh-installer-marker` と比較し、変わっていたら再 run する。

| 動作 | 条件 |
|---|---|
| fetch + 再 run | marker と sha が違う |
| fetch のみ、再 run skip | sha 一致(marker mtime を bump して TTL 延長) |
| 全 skip | marker が `CLAUDE_REFRESH_TTL` (default 300s) 以内 |
| fail-open | curl 失敗・sha 計算失敗時は warning 出して継続 |

env override:

| 変数 | 既定値 | 用途 |
|---|---|---|
| `CLAUDE_MD_INSTALL_URL` | `https://raw.githubusercontent.com/ippoan/claude-md/main/.claude/install.sh` | refresh hook が fetch する install.sh URL |
| `CLAUDE_REFRESH_MARKER` | `$CLAUDE_HOME/.refresh-installer-marker` | 最後に install した install.sh の sha256 を保存 |
| `CLAUDE_REFRESH_TTL` | `300` | network check skip TTL (秒) |

#### ⚠️ 1 session 遅延する変更

Claude Code は session 起動時に `~/.claude/settings.json` と `~/.claude.json` を読んでメモリに hold するため、これらの内容変更は **当該 session には反映されない**。refresh hook は disk を更新するが、Claude Code は再 read しない。

| 変更 | 反映 |
|---|---|
| `permissions.allow/deny/ask` 追加 | 次 session |
| `hooks.<event>` 追加(新規 hook 登録) | 次 session |
| `~/.claude.json` `mcpServers` 追加 | 次 session |
| 既存 `hooks/*.sh` の中身修正 | 即時(hook 発火時に disk read) |
| skills / sources / cc-relay clone の更新 | 即時 |

→ permissions / mcpServers / 新規 hook 登録を即時反映したい場合のみ Setup script 欄に `# bust YYYYMMDD-HHMMSS` 等を追加して保存し直す。それ以外の変更は何もしない。

#### worked example: hook 単独編集が既存 CCoW env に届くまで

`session-start-install-hooks.sh` だけを編集する PR (例: PR #18 — key-skills ✓/✗ 出力追加) を例に、既存 env がどう新 hook を受け取るかを追う:

1. PR が main へ merge される
2. GitHub Actions `stamp-install-sh-version.yml` が起動
3. workflow は変更された hook の新 sha256 を計算
4. install.sh 内の `HOOK_SHAS=...` ブロックの該当行をその新 sha に書き換えて main へ自動 push (workflow が直接 commit)
5. **install.sh 自体の sha も書き換えに伴って変わる** ← この点が PR #17 で導入された肝
6. 既存 CCoW env で次の session が始まる時、`session-start-refresh-installer.sh` が:
   - `CLAUDE_MD_INSTALL_URL` から新 install.sh を fetch
   - sha を計算 → `.refresh-installer-marker` の sha と違う → 再実行
   - install.sh が curl で新 hook を `~/.claude/hooks/` に上書き配置
   - marker を新 sha で更新
7. 同じ session 内ですぐ `install-hooks` hook が新版で走る (hook ファイルは hook 発火時に disk から再 read されるため即時)

PR #17 以前は (4) の HOOK_SHAS 機構が無く、hook ファイルだけ変えても install.sh の中身は不変 → sha も不変 → refresh-installer は「変わっていない」と判定 → 既存 env は古い hook を使い続ける、というリグレッションがあった。HOOK_SHAS により hook content が install.sh の sha の関数となり、hook-only 変更でも再配布がトリガーされる。

参考:
- [`anthropics/claude-code` #30737](https://github.com/anthropics/claude-code/issues/30737) — Allow reloading permissions/settings in a running session
- [`anthropics/claude-code` #5513](https://github.com/anthropics/claude-code/issues/5513) — `/reloadSettings` feature request
- [`anthropics/claude-code` #33829](https://github.com/anthropics/claude-code/issues/33829) — Hot-reload permissions from settings.local.json
- [Claude Code on the web — Setup script cache](https://code.claude.com/docs/en/claude-code-on-the-web#environment-caching)

### User memory (`.claude/user-memory.md` → `~/.claude/CLAUDE.md`)

応答言語 default を日本語にするための仕組み。Claude Code の `settings.json` schema には `locale` / `language` に相当する key が存在しない ([#26](https://github.com/ippoan/claude-md/issues/26)) ため、user memory (`~/.claude/CLAUDE.md`) 経由で注入する。settings.json 側の `locale: "ja"` は forward-compatible な hint で、現状 Claude Code は ignore する。

挙動:

- install.sh の段階 2 で `.claude/user-memory.md` を fetch
- `~/.claude/CLAUDE.md` の marker block (`<!-- BEGIN claude-md user-memory:locale -->` … `<!-- END … -->`) を idempotent に書き換える
- marker block の外は user の手書き内容として保護される (append でも overwrite でもない、in-place replace)
- block 不在の場合は file 末尾に追記。file 自体が不在なら新規作成

env override:

| 変数 | 既定値 | 用途 |
|---|---|---|
| `CLAUDE_USER_MEMORY_URL` | `$CLAUDE_MD_BASE_URL/.claude/user-memory.md` | user-memory.md の URL |
| `CLAUDE_USER_MEMORY_DEST` | `$CLAUDE_HOME/CLAUDE.md` | install 先 |
| `SKIP_USER_MEMORY` | unset | `1` で完全 skip (global で英語応答にしたい時) |

opt-out:

- **repo ごとに英語応答** にしたい場合は project の `./CLAUDE.md` に `Respond in English.` と書く (project memory は user memory より優先される)
- **全 session で英語応答** にしたい場合は CCoW Setup script の env で `SKIP_USER_MEMORY=1` を立てる
- user memory を **block ごと削除** しても install.sh の次回 run で再生成される (= 削除は永続しない)。永続したい場合は上記 SKIP env を使うか、marker 内テキストを書き換えるのではなく marker 外に英語指示を追記して project 側 override に頼る

### Drift 警告 hook (`session-start-snapshot.sh` + `pre-tool-claude-dir-drift.sh`)

CCoW container は ephemeral。session 中に `~/.claude/settings.json` や `~/.claude/hooks/` を弄っても container 終了で消える。これを **`git commit` のタイミングで Claude に気付かせる** のが本 hook ペアの役割。意図的な変更なら claude-md template repo に sync back する fallback path を warning 内で提示する。

| hook | trigger | 動作 |
|---|---|---|
| `session-start-snapshot.sh` | SessionStart | `~/.claude` 配下 (`*.json` / `*.sh` / `*.md` / `*.toml`、`projects/` `sources/` `cache/` `tool-results/` 除外) の sha256 baseline を `~/.claude/.session-snapshot` に保存 |
| `pre-tool-claude-dir-drift.sh` | PreToolUse, matcher=`Bash` | `tool_input.command` に `git commit` が独立 subcommand として現れる場合のみ snapshot と現状を diff。差分があれば非 blocking warning を `additionalContext` で Claude に inject |

挙動の特徴:

- **非 blocking**: hook 終了 code は常に 0。`git commit` 自体は止めない。Claude に判断させる
- **subcommand 境界判定**: `git commit-tree` / `git commit-graph` / path 中の `git commit` 等は false positive にならない (PR #5 のテストで pass)
- **snapshot 不在時は静音**: 古い `install.sh` 由来の env で snapshot hook が未配置なら drift hook も何も出さない (graceful degrade)
- **harness 実発火確認**: session 中盤で settings.json を上書きしても、**直後の Bash 呼び出しから** harness が新 hook を実行する ([検証 issue #6](https://github.com/ippoan/claude-md/issues/6))

env override:

| 変数 | 既定値 | 用途 |
|---|---|---|
| `CLAUDE_DRIFT_SNAPSHOT` | `$CLAUDE_HOME/.session-snapshot` | snapshot file path |
| `CLAUDE_DRIFT_MAX_FILES` | `10` | warning に列挙する最大 file 数 |

### MCP relay bootstrap (`install.sh` + `session-start-install-mcp-relay.sh`)

ippoan/mcp-relay-rs の 2 binary (`github-mcp-server-rs` + `ref-files-mcp-server-rs`) を Option C multiplex として 1 WebSocket bridge に乗せて mcp(-staging).ippoan.org に attach するための **責務分担した 2 段構成**。

#### 責務の分担

| stage | 担当 file | 動くタイミング | 役割 |
|---|---|---|---|
| Setup script | `.claude/install.sh` | CCoW container 起動時 (= 1 回だけ) | OAT-based grant が 200 を返せるなら `~/.claude.json` の `mcpServers` に `github-mcp-server-rs` + `ref-files-mcp-server-rs` entry を `binding_jwt` 込みで登録 + token cache file を焼く。**ここで entry が登録されるかで Claude Code が起動時に 2 server を deferred tool として認識できるかが決まる**。 |
| SessionStart | `session-start-install-mcp-relay.sh` | 毎 session 起動時 | Setup 時点で grant が 404 だった場合 (= OAT 未 bind = 初回 container) に additionalContext で Claude に register orchestration を要請。Claude が register 完了させると以降の container で install.sh の grant 200 path に乗る。同時に bridge process (= WS をぶら下げる binary) も spawn する。 |

CCoW container は ephemeral なので、Setup script は container 毎に 1 回走る。`~/.claude.json` の `mcpServers` 登録は **install.sh が write しない限り、hook が後で write しても本 session には反映されない** (Claude Code は session 起動時に `~/.claude.json` を memory に read してそれ以降 disk を見ない)。したがって OAT-bound 状態を `~/.claude.json` に反映する責務は install.sh 側にある。

#### OAT-based silent bootstrap (issue ippoan/auth-worker#174)

CCoW container には `/home/claude/.claude/remote/.oauth_token` に Anthropic OAT (`sk-ant-oat01-...`) が常駐するが、Anthropic identity endpoint は OAT を 403 で reject するため、OAT alone で github_login を引く path は無い。**OAT_hash → github_login の対応を auth-worker KV に bind**しておけば、以降 OAT を hash して lookup するだけで silent に binding_jwt が取れる。

auth-worker 側の 2 endpoint:

1. **`POST /mcp/pair/grant-via-oat`** — `Authorization: Bearer <OAT>` で叩き、KV bind 済みなら `binding_jwt` + `github_login` を取得。install.sh + hook の両方で使う。404 (= 未 bind) なら次の step。
2. **`POST /mcp/pair/register-via-github-comment`** — 404 を受けた hook が additionalContext で Claude に要請。Claude は `mcp__github__add_issue_comment` で tracking issue (default: ippoan/auth-worker#174) に `oat-binding: <oat_hash> <nonce>` を投稿し、その comment URL を register endpoint に POST。auth-worker は anonymous で GitHub API を叩いて `comment.user.login` を root-of-trust に取得、KV に 30d TTL で焼く。以降 fresh container で grant-via-oat 即 200。

```
[初回 container = OAT 未 bind]
1. Setup script install.sh:
   - grant-via-oat → 404 → mcpServers entry 登録 skip
2. session-start-install-mcp-relay.sh:
   - grant-via-oat → 404 → additionalContext で register 手順を提示
3. Claude が orchestrate:
   - mcp__github__add_issue_comment + POST register-via-github-comment → KV bind
   - 再 grant-via-oat 200 → token cache file 焼く (本 session の bridge は立つが
     Claude Code の mcpServers list には未登録なので tool は見えない)
4. 次の container 起動

[次の container = OAT 既 bind]
1. Setup script install.sh:
   - grant-via-oat → 200 → ~/.claude.json mcpServers に entry 登録 + token cache 焼く
2. Claude Code session 起動 — mcpServers から 2 server を認識
3. session-start-install-mcp-relay.sh:
   - token cache 既に存在 → install-mcp(-ref-files).sh を実行、bridge を spawn
4. Claude が mcp__github-mcp-server-rs__* / mcp__ref-files-mcp-server-rs__* を deferred tool として load 可能
```

#### 偽装耐性 (auth-worker 側で担保)

| 攻撃 | 防御 |
|---|---|
| 他人の login で comment 投げる | `mcp__github__add_issue_comment` は CCoW session の user identity でしか動かない (Anthropic proxy 経由)、不可能 |
| 自分の OAT_hash を他人の comment に書いた風に偽造 | comment は GitHub server-side で `user.login` を enforce、auth-worker が anonymous API で直接 fetch して検証 |
| 自分の OAT_hash を tracking issue に書いて他人になりすまし | `comment.user.login` = 自分の login で record される → 自分の login にしか bind しない (自爆) |
| OAT 漏洩 | rate limit per OAT_hash 10/min、Anthropic API で revoke 反映を即時検出 |

#### Legacy bootstrap path

OAT が読めない / `SKIP_OAT_BINDING=1` / register 未完了の時は従来の path を試す:

- `GITHUB_LOGIN` + `GITHUB_MCP_TOKEN_JSON` / `REF_FILES_MCP_TOKEN_JSON` が CCoW Setup-script secret として set されていれば、install.sh が `~/.claude.json` に entry を登録 + install-mcp.sh が token cache JSON を hydrate して silent bootstrap
- 上記 token JSON も無い場合は 1-click pair flow に fall back し、pair URL を additionalContext に出して user の click を待つ

#### 失敗時の挙動

- install.sh の OAT grant が curl fail / 5xx / 404 / 401 — silent skip、`~/.claude.json` は cc-relay のみで完成、hook の register orchestration path に fall through
- hook の OAT grant が同様に失敗 — additionalContext に状況を記載して終了 (fail-open)
- install-mcp.sh / install-mcp-ref-files.sh が exit≠0 — `github=fail` / `ref-files=fail` を additionalContext に表示。session 自体は止めない

### env override

| 変数 | 既定値 | 用途 |
|---|---|---|
| `CLAUDE_MD_BASE_URL` | `https://raw.githubusercontent.com/ippoan/claude-md/main` | claude-md raw base URL。**branch 切替の単一窓口** (PR テスト用) |
| `CLAUDE_MD_TEMPLATE_URL` | `$CLAUDE_MD_BASE_URL/.claude/settings.json.template` | settings.json template の URL (個別上書き) |
| `CLAUDE_USER_MEMORY_URL` | `$CLAUDE_MD_BASE_URL/.claude/user-memory.md` | user-memory.md の URL (個別上書き) |
| `CLAUDE_USER_MEMORY_DEST` | `$CLAUDE_HOME/CLAUDE.md` | user-level CLAUDE.md install 先 |
| `CLAUDE_HOOK_URL` | `$CLAUDE_MD_BASE_URL/.claude/hooks/session-start-install-hooks.sh` | SessionStart hook script の URL (個別上書き) |
| `CLAUDE_HOME` | `/root/.claude` | `.claude` dir |
| `CLAUDE_SETTINGS_DEST` | `$CLAUDE_HOME/settings.json` | settings.json install 先 |
| `CLAUDE_JSON_DEST` | `/root/.claude.json` | MCP 登録先 |
| `CC_RELAY_REPO` | `https://github.com/ippoan/cc-relay.git` | cc-relay clone URL |
| `CC_RELAY_DIR` | `/home/user/cc-relay` (CCoW) / `$HOME/cc-relay` | cc-relay clone 先 |
| `CC_RELAY_MCP_URL` | `https://mcp.ippoan.org/mcp` (prod) | user-level MCP server URL。staging 切替: `https://mcp-staging.ippoan.org/mcp` |
| `GITHUB_MCP_URL_BASE` | `https://mcp.ippoan.org` | github-mcp-server-rs relay の base URL (admin 用)。staging override: `https://mcp-staging.ippoan.org` |
| `GITHUB_MCP_ADMIN_TOKEN_JSON` | unset | `auth --scope mcp.admin` で焼いた token cache JSON。set すると `github-mcp-admin` MCP entry を `~/.claude.json` に追加 |
| `GITHUB_LOGIN` | unset | ippoan/mcp-relay-rs binaries (github-mcp-server-rs + ref-files-mcp-server-rs) を register する際の URL に埋め込む github username。CCoW Setup-script secret として export 推奨 |
| `MCP_RELAY_URL_BASE` | `$GITHUB_MCP_URL_BASE` | mcp-relay-rs binaries の relay base URL。staging 切替: `https://mcp-staging.ippoan.org` |
| `GITHUB_MCP_TOKEN_JSON` | unset | mcp-relay 登録時の `github-mcp-server-rs` entry に `Authorization: Bearer` header を埋め込む token cache JSON (silent bootstrap)。同名 env を install-mcp.sh hook が binary 側 token cache hydrate にも使う |
| `REF_FILES_MCP_TOKEN_JSON` | unset | 同上、`ref-files-mcp-server-rs` 用 |
| `SECRETS_INVENTORY_MCP_URL` | `https://security-inventory.ippoan.org/mcp` | secrets-inventory read-only mcpServer の URL (Refs ippoan/secrets-inventory#61) |
| `SECRETS_INVENTORY_AUTH_ORIGIN` | `https://auth.ippoan.org` (prod) | secrets-inventory 用 read-only `binding_jwt` を mint する auth-worker origin。prod RS は prod auth-worker に introspect するため staging 不可 |
| `SKIP_SETTINGS` / `SKIP_USER_MEMORY` / `SKIP_HOOK` / `SKIP_CC_RELAY` / `SKIP_MCP` | unset | `1` で各段階 skip |
| `SKIP_GITHUB_MCP_ADMIN` / `SKIP_MCP_RELAY` | unset | `1` で個別 MCP entry を skip (URL register のみ skip。SKIP_MCP=1 だと全部 skip) |
| `SKIP_SECRETS_INVENTORY_MCP` | unset | `1` で secrets-inventory read-only mcpServer 登録を skip + 既存 entry 除去 |
| `CLAUDE_HOOKS_MCP_RELAY_BRANCH` | `main` | session-start-install-mcp-relay.sh が install-mcp(-ref-files).sh を fetch する ippoan/mcp-relay-rs branch |
| `SKIP_INSTALL_MCP_RELAY` | unset | `1` で session-start-install-mcp-relay.sh hook 全体を skip (URL register は別軸) |
| `AUTH_WORKER_ORIGIN` | `https://auth-staging.ippoan.org` | OAT-based bootstrap (`/mcp/pair/grant-via-oat` + register, issue ippoan/auth-worker#174) で叩く auth-worker origin。install.sh (Setup script 段階の `~/.claude.json` mcpServers 登録) と session-start-install-mcp-relay.sh (token cache hydrate + register orchestration) の両方が参照する。prod 切替: `https://auth.ippoan.org` |
| `SKIP_OAT_BINDING` | unset | `1` で OAT-based silent bootstrap (issue #174) を install.sh + hook の両方で skip。legacy env/token cache の path のみで bootstrap する |
| `OAT_BINDING_TRACKING_REPO` | `ippoan/auth-worker` | OAT register endpoint で identity proof として使う GitHub issue comment の投稿先 owner/repo |
| `OAT_BINDING_TRACKING_ISSUE` | `174` | 同上 issue number。本 issue 自体を tracking 用に兼用する設計 |
| `CLAUDE_INSTALL_STAMP` | `$CLAUDE_HOME/.install-stamp` | stamp ファイル path。`cat` 1 発で `install_sh_version` と `iso` 時刻を確認でき、setup script で走ったか cache 由来かを判別できる |
| `CLAUDE_HOOKS_INSTALL_TTL` | `3600` | hook 側: network sync を skip する TTL (秒) |
| `CLAUDE_HOOKS_SCAN_DIRS` | `/home/user` | hook 側: attached repo を探す親 dir |
| `CLAUDE_HOOKS_KEY_SKILLS` | `skill-creator open-multirepo` | hook 側: key-skills ✓/✗ check 対象 (space 区切り) |

### 運用

- **session 冒頭で 1 回 paste** — 1 行 (上記の A or B) を冒頭 prompt に貼り付け。書き込み直後の tool call から runtime が新 allow list を読む (= 即時反映)。
- **CCoW environment の Setup script に登録 (推奨)** — Environment → Setup script 欄に同じ 1 行を貼ると container 起動時に 1 回走る。毎 session の paste 不要。詳細は https://code.claude.com/docs/en/claude-code-on-the-web 。
- 更新フロー: 通常は何もしない (`session-start-refresh-installer.sh` が毎 session 自動で main の最新を取り直す)。permissions/mcpServers の追加だけ即時反映が必要なら `# bust YYYYMMDD-HHMMSS` を編集 + 保存 → 次 session で新 install.sh。

### A/B 共通

- 各段階で `[install.sh] …` プレフィクス付きでログを出すので、Setup script ログ / session の最初の Bash 結果で成否を確認できる。
- SessionStart hook の結果は session 起動時の hook log (additionalContext) で確認できる: `install-hooks: synced via proxy (skills=28) ok` 等
- project-level `.claude/settings.json` (repo の中に commit する形) と併用可能。重複は project 側が勝つ。

## Tool 使用許可テンプレート (`.claude/settings.json.template`)

bootstrap の段階 1 で install される user-level template。`~/.claude/settings.json` に置けば repo attach に関係なく effective になる (= cross-repo の cc-relay / auth-worker / claude-hooks 系セッションで permission prompt を減らせる)。`hooks` セクションには SessionStart 2 本 + PreToolUse 1 本 (matcher=Bash) を登録済 (詳細は前節)。

### 中身 (要旨)

| 区分 | 例 |
|---|---|
| locale | `locale: "ja"` (forward-compatible — 現状 Claude Code は schema 外 key として ignore するが、実 locale source は user-memory 経由) + `env.LANG=ja_JP.UTF-8` / `env.LC_ALL=ja_JP.UTF-8` |
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
- 参照元 repo: `ippoan/{cc-relay,auth-worker,ci-dashboard,claude-hooks,claude-skills}`
