# Portfolio Page

Masaru Funahashiのゲーム翻訳者ポートフォリオ。静的HTMLとTailwind CSS（CDN）で構築し、既存のDocker Swarm上のNginxからCloudflare Tunnel経由で公開する。

- サイト: <https://clamm-translation.net>
- GitHub: <https://github.com/clamm0363/Portfolio-Page>
- 作業ルール: [AGENTS.md](AGENTS.md)
- 公開・検証・切り戻しの正本: [DEPLOYMENT.md](DEPLOYMENT.md)

## 編集するファイル

| 対象 | ファイル |
| --- | --- |
| 本文・レイアウト・クライアント側処理 | `index.html` |
| サイト内画像 | `assets/images/` |
| 配信・キャッシュ・Umami中継 | `nginx/nginx.conf` |
| Nginx限定更新 | `deploy-portfolio.ps1`、`scripts/start-site.sh` |
| 過去の全体構成の参考資料 | `docker-compose.yml`（現環境へそのまま反映しない） |

## 日常の流れ

1. 専用branchで編集し、表示・リンク等を必要な範囲で確認する。
2. 必要なレビューとGitHubのチェックを経てPRをmainへmergeする。
3. PowerShell 7.4以上で公開スクリプトの`Plan`を実行し、対象・固定commit・保持されるimage・変更前version・候補hashを確認する。
4. 同じ計画の`Apply`でNginxだけを更新する。
5. タスク収束・内部配信元・公開サイトの機械確認と、ブラウザの表示・リンク確認を行い、適用commitを記録する。

コマンド、初回準備、失敗時の復帰は[公開手順](DEPLOYMENT.md)に集約する。mainへのmergeだけでは公開完了にならない。

## 実行環境

WindowsのPowerShellとGit、既存のPortainer API資格を利用する。日常更新にDocker Desktop、WSL、SSH、新しいGitHub Actionsやコンテナregistryは不要。`.env`と`.local/`はローカル限定とし、Gitへ登録しない。

稼働中の配信環境や付帯サービスの保守は、コンテンツ公開と分ける。過去の構成例で現行設定を上書きしない。
