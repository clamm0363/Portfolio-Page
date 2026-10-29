# 公開・検証・切り戻し

この文書を公開手順の正本とする。対象は、GitHubの採用済みcommitを既存のNginxサービスへ反映する日常更新。PowerShell 7.4以上と既存Portainerを使う。

## 更新方式

`deploy-portfolio.ps1`は既定で読み取り専用の`Plan`を行う。`Apply`では現在のサービス仕様を読み、起動処理・配信commit・ヘルスチェック・更新方式だけを変更し、Nginx一サービスの更新APIを一度だけ呼ぶ。Stackの削除・作成・全体再デプロイ、imageのpull/変更、DB・Umami・Tunnelの操作は行わない。

Nginxの起動処理は`main`ではなく40桁SHAをfetchし、取得SHAの一致、ファイル配置、`nginx -t`の成功後に配信を開始する。`release.json`に配信commitを記録する。更新は`start-first`、異常時は`pause`とする。無停止を保証するものではなく、起動時のGitHub・Alpine配信元への接続失敗やリソース不足では更新が止まり得る。

コンテンツをimageへ組み込む方式は起動時の外部依存を減らせるが、現在の稼働imageを保つためのビルド・registry・配布経路を新設する必要がある。この環境では既存の固定imageとPortainerを維持し、配信ソースだけをSHA固定する。imageの更新やビルド方式の変更は別作業とする。

## 初回準備

1. 現行[AGENTS.md](AGENTS.md)の承認境界を確認する。手順修正とローカル検証の成功を、実環境へ適用済みとは扱わない。
2. `.env`の`PORTAINER_URL`と`PORTAINER_API_TOKEN`を既存の値で設定する。秘密値をコマンド引数・会話・Git・記録へ出さない。他の既存キーは保持する。日常公開ではDBやTunnelの秘密値を読み出して再送しない。
3. `.local/deployment-environment.json`へ確認済みの接続対象を保存する。既存ファイルがあれば上書きせず現状を確認する。例は以下のとおりで、ID・origin・既知の公開commitは実環境から確認した値に置き換える。

```json
{
  "EndpointId": 1,
  "StackId": 1,
  "StackName": "portfolio-site",
  "OriginUrl": "http://SWARM_NODE:8001",
  "PublicUrl": "https://clamm-translation.net",
  "PreviousCommit": "FULL_40_CHARACTER_DEPLOYED_COMMIT_SHA"
}
```

originは既存のSwarm ingressに到達する内部URLを使う。Portainer URLとorigin URLは別の入口である。追加のポート公開・DNS変更・Cloudflare保護解除は行わない。IDは過去の値を無条件に使わず、Stackのendpoint・名前・Git接続先と照合する。スクリプトも照合し、自動Stack更新が有効なら停止する。

4. 配信元が未固定の初回は、既知の公開commitを履歴から特定する。`Plan`はそのcommitのHTML・参照画像とoriginのバイト一致を要求する。不一致なら未記録変更やcacheを調べ、推測で上書きしない。
5. この更新コードをmainへ採用し、ローカルmainと作業コードを同期する。実行コードは別AIレビューとオフライン検証を済ませる。最初の固定化だけでもNginxタスクの入替えを伴う。既存imageが配置先で利用可能なこと、GitHub/Alpine接続条件、短時間の接続影響を確認する。

## 日常更新

main採用前に対象のHTML・画像・表示・リンクを確認する。Nginx設定を変えた場合は設定検証も行う。DockerのないこのWindows環境で`nginx -t`を実施したことにはせず、必要なら承認済みの隔離検証環境を使う。起動処理にも`nginx -t`があり、不正な候補では新Nginxを起動しない。

mainへmerge後、GitHubとローカルの採用版を確認する。

```powershell
git fetch origin
# fetch失敗なら続行せず、採用版を確認する。
$portfolioCommit = git rev-parse origin/main
$portfolioContext = Get-Content .local/deployment-environment.json -Raw | ConvertFrom-Json -AsHashtable
$portfolioPlan = .\deploy-portfolio.ps1 @portfolioContext -Mode Plan -Commit $portfolioCommit | ConvertFrom-Json
$portfolioPlan
```

スクリプトは指定SHAがローカル`origin/main`の履歴に含まれることも確認する。Planに表示される対象、旧/新commit、image、version、候補仕様hashを確認する。初回の固定化では旧/新commitが同じでもよい。

```powershell
New-Item -ItemType Directory -Force .local | Out-Null
$portfolioPlan | ConvertTo-Json -Depth 5 | Set-Content .local/last-plan.json -Encoding utf8
.\deploy-portfolio.ps1 @portfolioContext -Mode Apply -Commit $portfolioCommit `
  -ExpectedVersion $portfolioPlan.ExpectedVersion `
  -ExpectedSpecSha256 $portfolioPlan.ProposedSpecSha256
```

`Apply -WhatIf`は変更APIを呼ばず、同じ事前確認まで行う。Plan以降にサービスversionやローカル起動スクリプトが変わった場合はApplyを止め、新しいPlanを作る。更新APIの失敗・timeoutは成否不明の場合があるため、Applyを再送せず現在のサービス・タスク・originを読み直す。

## 完了確認

Applyは更新完了・期待SHAのタスク収束、originのHTML・参照画像・release marker、公開marker・HTML・参照画像を確認する。他サービスの仕様が処理中に変わっていれば報告し、その変更を自動で戻さない。

Cloudflareはこのサイトのメール保護とbeacon挿入でHTMLを変換する。originはバイト単位で照合し、公開HTMLは確認済みの2つの変換と空白の差だけを除いて照合する。未知の変換を無条件で無視しない。画像の差や古い公開内容はcache等を確認し、完了扱いにしない。

独立した読取確認は次のとおり。

```powershell
.\deploy-portfolio.ps1 @portfolioContext -Mode Verify -Commit $portfolioCommit
```

さらにブラウザで広い画面・狭い画面、今回の変更、画像、主要リンク・メニュー等を確認する。外部の問い合わせ送信は行わない。API受付・`/health`の200だけでは完了としない。

確認後、IssueまたはPR一か所へ適用commit、実施日、確認内容、残件を記録し、ローカルの既知公開版を更新する。直前のPlanは切り戻し対象の証跡として保持する。

```powershell
$portfolioContext.PreviousCommit = $portfolioCommit
$portfolioContext | ConvertTo-Json | Set-Content .local/deployment-environment.json -Encoding utf8
```

## 切り戻し

通常は直前のPlanの`PreviousCommit`へ、同じNginx限定更新で復帰する。`docker service rollback`はサービス仕様の復帰であり、旧仕様が`main`を取得する構成なら旧コンテンツに戻る保証がない。本手順では、復帰先も固定SHAにする。

公開中の内容が正常で照合可能なら、現在のcommitをPreviousCommit、復帰先をCommitとして通常のPlan→Applyを行う。更新がpause・途中・不明状態で通常Planが止まる場合に限り、先にサービス仕様・タスク・originと保存済みPlanを調べ、今回の更新の復旧であることを確認して`-Recovery`を使う。

```powershell
$portfolioSavedPlan = Get-Content .local/last-plan.json -Raw | ConvertFrom-Json
$portfolioRecovery = $portfolioContext.Clone()
$portfolioRecovery.PreviousCommit = $portfolioSavedPlan.Commit
$portfolioRestoreCommit = $portfolioSavedPlan.PreviousCommit
$portfolioRestorePlan = .\deploy-portfolio.ps1 @portfolioRecovery -Mode Plan `
  -Commit $portfolioRestoreCommit -Recovery | ConvertFrom-Json
$portfolioRestorePlan
.\deploy-portfolio.ps1 @portfolioRecovery -Mode Apply -Recovery `
  -Commit $portfolioRestoreCommit -ExpectedVersion $portfolioRestorePlan.ExpectedVersion `
  -ExpectedSpecSha256 $portfolioRestorePlan.ProposedSpecSha256
```

Recoveryは旧コンテンツとの事前一致と既存タスク安定の条件だけを外し、対象確認・固定image保持・version/hash照合・復帰後の検証は維持する。復帰先が証跡で確定できない、他作業の変更がある、imageが失われた等の場合は止め、勝手にimage変更や全Stack再作成へ進まない。復帰後も公開・表示確認を行い、適用版と残件を記録する。

## 全体構成・共有基盤の変更

`docker-compose.yml`は過去の全体構成の参考資料である。実環境への全体適用には、稼働設定との事前照合が必要である。`docker stack deploy`、PortainerのPull and redeploy、Stack削除・再作成を日常更新に使わない。日常公開はPortainer管理のStack内の一サービスを直接更新するため、PortainerのGit配置履歴はコンテンツ公開履歴の正本にはならない。

全Stackの再デプロイが必要になった場合は、先にlive仕様と既存HomeLab正本を照合し、image digest・Env・Configs/Secrets・network・mount・DB接続先等を保持した候補を別作業で用意する。PortainerのGitOps自動更新やWebhookは有効にしない。過去のComposeを適用すると限定更新が上書きされる。DB・Tunnel・共有基盤へ影響する変更は、それぞれの所有プロジェクトの手順と承認条件に従う。

DBの初期化、liveデータディレクトリのtarコピーによる整合性未確認のbackup、架空のホスト名での復元、デフォルト資格の利用、TLS検証無効化を公開手順へ含めない。DB backup/restoreは現在のDB所有者と構成を確認して専用手順で扱う。

## 根拠と検証

- [Docker: service更新](https://docs.docker.com/reference/cli/docker/service/update/)と[Compose deploy仕様](https://docs.docker.com/reference/compose-file/deploy/): start-first、更新監視・失敗時動作を明示する。起動状態と公開成功を分ける。
- [Docker: rollback](https://docs.docker.com/reference/cli/docker/service/rollback/): 戻す対象は直前のサービス設定であり、起動時に移動branchを取得するアプリの配信内容固定は別途必要。
- [Portainer: GitOps更新の仕組み](https://docs.portainer.io/faqs/troubleshooting/stacks-deployments-and-updates/how-do-automatic-updates-for-stacks-applications-work): Git取得は全Stackのdeploy経路であり、通常のGit更新確認だけで起動時cloneを使う静的内容の更新は保証されない。
- [2026-10-30の点検記録](docs/deployment-review-2026-10-30.md)。ローカル検証は`pwsh -NoProfile -File tests/test-deployment.ps1`。
