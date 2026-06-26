# Variant: Cloudflare Worker (+ shared npm package)

`CLAUDE.md.template` の §4 (ビルド/テスト/lint) と §6 (GitHub 自動化) を
Cloudflare Workers + workspace npm package 向けに差し替えるための snippet。
`ippoan/auth-worker` で使われている形。

## §4 差し替え: ビルド / テスト / lint

````md
PR を出す前に手元で全部 green であること:

```sh
npm test                  # vitest
npm run typecheck         # vue-tsc + tsc --noEmit
npm run lint              # eslint (設定されていれば)
npm run coverage          # 100% gate がある場合
```

worker 単体の dev/run は `wrangler dev` だが、それは hooks (deploy-guard.sh)
に拾われない範囲で叩ける。**`wrangler deploy` は CI 経由でしか走らせない** —
ローカル叩きは `claude-hooks/deploy-guard.sh` が block する。
````

### Required status checks (§6 内)

```
test
typecheck
coverage  (該当 repo のみ)
publish-dev (該当 repo のみ — auth-client の packages/* publish)
```

## 末尾追加セクション

### packages/ — npm として ship する shared library がある場合

```md
## packages/<name> パッケージ

### 型安全性

`packages/<name>` は `.vue` / `.ts` ソースをそのまま ship する (ビルドステップ無し)。
消費側の `nuxi typecheck` (vue-tsc) がソースを直接型チェックするため、
**全ての `.vue` / `.ts` ファイルで strict な型注釈が必要**。

- `fetch().json()` の戻り値には必ず `as Type` を付ける (vue-tsc v5 では `unknown`)
- `Array()` リテラルには型注釈を付ける (`const parts: string[] = []`)
- `catch (e)` には `catch (e: unknown)` または `catch (e: any)` を明示

### Publish フロー

- PR → CI `Publish Dev` で dev タグ publish
- merge + `v*` タグ → `Publish Release` で latest publish
- `npm_publish_directory: 'packages/<name>'` (test.yml)

### 消費側の version pin (staging=dev / prod=v タグ)

`@ippoan/*` lib を consume する側は **channel を環境に揃える**:

- **staging consumer** (PR auto-deploy / single-env=staging) → `package.json` は
  **`dev` dist-tag** に pin。新 export を出した直後の検証はこの channel で回す。
  test.yml に **`use_auth_client_dev: true`** (frontend-ci の overlay action) を
  足すと、PR event で `npm install <pkg>@dev` を lockfile の後に上書き install
  するので、stable 未掲載の新 export でも PR/staging が green になる。
- **prod consumer** (`v*` タグで本番 deploy) → **stable `v*` (caret pin)**。
  **`dev` を実 prod に届かせない** (壊れた dev で本番が割れるのを防ぐ)。
  prod タグを切る前に `package.json` を `dev` → stable へ bump する (step 化)。

> 新 export を stable に出した後も、移行 PR は **まず dev で staging 検証 →
> green を確認してから stable bump** の順を守る。`push`(main) event では overlay が
> 走らないので、dev pin のまま main に merge すると main typecheck が赤になり得る
> (dev チャネル運用の既知トレードオフ。stable bump で解消)。

### 消費側 repo

| リポジトリ | 使用 export |
|---|---|
| <consumer-repo-1> | <Component / hook 名> |
| <consumer-repo-2> | (同上) |

新しい consumer を足したらこの表を更新する (検索のため)。
```

### Cloudflare 固有の運用メモ

```md
## Cloudflare Workers 固有

### Wrangler / 環境

- `wrangler.toml` の `[env.staging]` / `[env.production]` を分ける
- secrets は `wrangler secret put <KEY> --env <env>` で投入 (repo に commit しない)
- KV / D1 binding は `wrangler.toml` で宣言、CI でも同名で参照されることを確認

### Staging vs Production

- ステージング: `<service>-staging.<domain>` (例: `auth-staging.ippoan.org`)
- 本番: `<service>.<domain>` (例: `auth.ippoan.org`)
- **staging が live でない PR を本番に merge しない** — Probe:
  ```sh
  curl -s -o /dev/null -w "%{http_code}\n" -X POST https://<service>-staging.<domain>/<endpoint>
  ```
  期待: 200/401 (404 なら未 deploy)
```

## 破壊厳禁ルール追加 (§「やってはいけないこと」末尾)

```md
- `wrangler deploy` をローカル / 手元で叩かない (CI のみ)。
- `wrangler secret` で投入した値を `wrangler.toml` / `.dev.vars` に書き戻さない。
- workspace の `package.json` の `engines.node` を CI と乖離させない
  (Workerd runtime 互換の Node 版を必ず指定)。
```
