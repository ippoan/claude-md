# Variant: Rust workspace

`CLAUDE.md.template` の §4 (ビルド/テスト/lint) と §6 (GitHub 自動化) を Rust
workspace 向けに差し替えるための snippet。`ippoan/cc-relay` で使われている形。

## §4 差し替え: ビルド / テスト / lint

````md
PR を出す前に手元で全部 green であること:

```sh
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

CI (`.github/workflows/ci.yml`) は `main` への PR ごとに上の 3 つを
matrix で回す。crate を追加した時は `Cargo.toml` の `members =` に
忘れず append すること (workspace 解決から外れると CI で test が漏れる)。
````

### Required status checks (§6 内)

```
rust (fmt)
rust (clippy)
rust (test)
```

(matrix job 名は CI workflow の `name:` と一致させる。`include` で os
matrix を切ってる場合は `rust (test, ubuntu-latest)` 等になる)

## 末尾追加セクション

### Wire protocol の変更 (該当する crate がある場合のみ)

```md
## Wire protocol の変更

`crates/<core-crate>/src/protocol.rs` が wire protocol の唯一の真実。
後方互換を壊す変更を入れる時は `PROTOCOL_VERSION` (現在 `<N>`) を上げる。

protocol を破壊的に変えると以下の consumer 全てに同期 update が必要:
- (ここに consumer repo / crate を列挙)
```

### Release / version bump

```md
## Release / version bump

tag を打つときは Cargo workspace の `workspace.package.version` を必ず
同時に bump する。`release.yml` (workflow_dispatch) は tag 名を受けて
release asset を build/publish するが、tag と `Cargo.toml` の version
が乖離すると binary の `--version` 出力が古い tag を表示する事故が起きる
(参考: cc-relay v0.0.3 では bump 漏れで `--version` が `0.0.0` を返した)。

手順:

1. `cargo set-version --workspace 0.0.<N>` (cargo-edit 入れてなければ手動で `Cargo.toml` 編集)
2. PR を出して merge
3. `gh workflow run tag-release.yml -f tag=v0.0.<N>` で tag + release を作る

`release.yml` 内で `Cargo.toml` の version と input tag が一致するかを検証する
step を入れると bump 漏れ事故が防げる (issue 化推奨)。
```

### Sub-agent 並列開発 (該当する場合のみ)

```md
## Sub-agent で並列開発する

本体 crate が動くまでの間、`Agent` tool で疑似的に multi-agent を組んで
開発を進めるパターン:

- **並列 crate 実装** (`isolation: "worktree"`) — 独立 crate を別 worktree
  で同時に書く。共有型 (`<core-crate>`) を触る変更には使わない。
- **背景 issue 更新** (`run_in_background: true`) — tracking issue に進捗
  コメントを淡々と投げる。本体は実装に集中。
- **PR 監視 / autofix** — `mcp__github__subscribe_pr_activity` で webhook
  待ち、CI failure 時に必要なら sub-agent に fix を委譲する。`sleep` /
  polling は禁止。

詳しい手順は [`docs/sub-agent-workflow.md`](./docs/sub-agent-workflow.md) と
[`examples/sub-agent-recipes/`](./examples/sub-agent-recipes/) を参照。
```

## 破壊厳禁ルール追加 (§「やってはいけないこと」末尾)

```md
- daemon を panic させない。runtime 経路の `Result` は全て log して
  捨てる、`main` まで bubble させない。
- `unsafe_code = "forbid"` を解除しない (workspace lints に縛られている)。
- `[profile.release]` の `lto` / `codegen-units` / `panic = "abort"` を
  外さない (binary size / startup time が悪化する)。
```
