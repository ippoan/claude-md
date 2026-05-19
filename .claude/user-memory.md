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
