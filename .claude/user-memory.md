## 応答言語

このセッションでは、特に指示がない限り **応答は日本語で行う**。

ただし以下は対象 repo の既存スタイル (英語の repo なら英語、日本語の repo なら日本語) に合わせる:

- コードコメント
- commit message
- PR title / description
- issue title / body
- code identifier / 変数名

### opt-out

repo ごとに英語応答にしたい場合は、その repo の `./CLAUDE.md` (project-level
memory) に `Respond in English.` と明記する。project memory が user memory より
優先される。

全 session で英語にしたい場合は CCoW environment の Setup script で
`SKIP_USER_MEMORY=1` を export してから install.sh を叩く。

## Claude による auto-merge enable は禁止

Claude Code セッションが `mcp__github__enable_pr_auto_merge` を呼ぶことは
**user が明示的に指示したとき以外は禁止**。reflex で叩かない。

### 理由 (実害ケース)

- branch protection の required status check が完全に揃っていない repo
  (新設 CI check が未追加 / `ci /` prefix を持たない workflow が混在 等) で
  auto-merge を enable すると、GitHub が「現時点で satisfied」と判定して
  **CI が走り切る前に即 merge** する事故が起きる
  (実害: `ippoan/secrets-inventory-gcp#21` / `ippoan/ci-dashboard#89` /
  `ippoan/secrets-inventory#37`)
- `ci-workflows/frontend-ci.yml` の `disable-auto-merge` step も Claude の enable
  call の "数秒後" に走るので race を防げない — GitHub 側の merge 判定の方が早い
- repo に `auto-merge.yml` workflow がある場合、CI green 完了後に workflow 自身が
  enable するので、Claude が事前 enable する必要はない

### 運用

- ✅ 推奨: PR を作ったら CI 結果を `subscribe_pr_activity` で待ち、green を
  確認した上で user が手動 merge する (または user が「auto-merge enable して」
  と明示指示する)
- ❌ 禁止: `mcp__github__create_pull_request` の直後に `enable_pr_auto_merge` を
  反射的に呼ぶ
- `/pr-push` skill は内部で必要な merge 制御を行うのでそちら経由なら OK
