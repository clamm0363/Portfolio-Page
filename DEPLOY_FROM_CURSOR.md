# AI・エディターからの公開

Cursor、Codex、その他のエディターで共通の[公開手順](DEPLOYMENT.md)を使う。手順をここへ複製しない。

通常は専用branchで編集・検証し、レビューとPR採用後に`deploy-portfolio.ps1`の`Plan`→`Apply`→公開・表示確認を行う。資格は既存`.env`から内部利用し、秘密値をコマンド引数へ渡さない。

旧版の「Stackを削除して作り直す」「mainへ直接push」「CephFSへ静的ファイルを直接コピー」「TLS検証を無効化」の手順は使用しない。承認条件・停止指定は[AGENTS.md](AGENTS.md)に従う。
