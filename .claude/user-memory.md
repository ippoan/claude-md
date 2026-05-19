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

## PR 作成後の auto-merge

`mcp__github__create_pull_request` で PR を作ったら、**同じ turn のうちに必ず**
`mcp__github__enable_pr_auto_merge` (`mergeMethod: "SQUASH"`) を呼んで auto-merge
を有効化する。CI green + required approval が揃った時点で自動 merge される運用
を前提にしているため、これを忘れると merge が止まる。

- 既に merge 済みの PR に呼ぶと `Pull request is already merged` が返るが
  no-op で無害
- branch protection / "Allow auto-merge" が repo 側で off の場合は graceful に
  失敗するが、その場合も呼ぶこと自体は試みる (失敗した repo は `/wt-direct-push`
  候補か再確認する)
- `/pr-push` skill 経由は内部で auto-merge を enable するので追加呼び出し不要。
  **手で `mcp__github__create_pull_request` を叩いた時** が落としやすいケース。
