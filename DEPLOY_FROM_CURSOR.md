# Cursor/AI からの自動デプロイガイド

このドキュメントは、Cursor IDE または別のAIセッションから、Portainer API経由でDocker Swarm Stackを自動デプロイする方法を説明します。

## 📋 目次

1. [システム概要](#システム概要)
2. [前提条件](#前提条件)
3. [デプロイ方法](#デプロイ方法)
4. [スクリプトの詳細動作](#スクリプトの詳細動作)
5. [トラブルシューティング](#トラブルシューティング)
6. [セキュリティ](#セキュリティ)

---

## システム概要

### アーキテクチャ

```
Cursor/AI
  ↓ (1) ファイル編集
  ↓ (2) git commit & push
  ↓ (3) .\deploy-portfolio.ps1 実行
  ↓
Portainer API (http://192.168.0.95:9000)
  ↓ (4) GitHub から docker-compose.yml 取得
  ↓ (5) Docker Swarm Stack デプロイ
  ↓
Docker Swarm クラスタ (3ノード)
  ↓ (6) サービス起動
  ↓
サイト公開 (https://clamm-translation.net)
```

### デプロイされるサービス

- **nginx**: 静的サイト（ポート8001 → Cloudflare Tunnel経由で公開）
- **umami**: セルフホストアナリティクス（ポート3002）
- **umami-db**: PostgreSQL データベース
- **cloudflared**: Cloudflare Tunnel（HTTPS公開）

### ストレージ

- **CephFS**: `/mnt/cephfs/portfolio/` （3ノード間で共有）
  - `html/`: 静的ファイル (index.html, assets/)
  - `db/`: PostgreSQL データ
  - `nginx/`: Nginx設定ファイル

---

## 前提条件

### 必須環境

✅ **ローカル環境**
- PowerShell 5.x 以上（推奨: PowerShell 7）
- Git がインストール済み
- `.env` ファイルが設定済み

✅ **インフラ**
- Docker Swarm クラスタが稼働中（3ノード）
- Portainer が稼働中（http://192.168.0.95:9000）
- CephFS が全ノードにマウント済み（`/mnt/cephfs/`）
- `public` overlay network が作成済み

✅ **環境変数（`.env`ファイル）**

必須の環境変数：

```env
# Cloudflare Tunnel Token
TUNNEL_TOKEN=eyJhIjoi...（実際のトークン）

# PostgreSQL Database
POSTGRES_DB=umami
POSTGRES_USER=umami
POSTGRES_PASSWORD=your-secure-password-here

# Umami Hash Salt (32バイトのランダム文字列)
UMAMI_HASH_SALT=your-random-64-character-hex-string-here

# Portainer API Token (必須)
PORTAINER_API_TOKEN=ptr_your_portainer_token_here

# Portainer URL (オプション、デフォルト: http://192.168.0.95:9000)
PORTAINER_URL=http://192.168.0.95:9000
```

### Portainer APIトークンの取得方法

1. Portainer UIにログイン: http://192.168.0.95:9000
2. 右上のユーザーアイコン → **My account**
3. **API keys** セクション → **Add API key**
4. Description: `Cursor Deployment`
5. トークンをコピーして `.env` ファイルに貼り付け

---

## デプロイ方法

### 基本的な使い方

#### 1. ファイルを編集

Cursor で `index.html` や他のファイルを編集します。

#### 2. Git にコミット＆プッシュ

```bash
git add .
git commit -m "Update: サイトの内容を更新"
git push origin main
```

#### 3. デプロイスクリプトを実行

Cursor のターミナル（PowerShell）で：

```powershell
.\deploy-portfolio.ps1
```

**または、AI に依頼する場合：**

```
deploy-portfolio.ps1 を実行してサイトをデプロイしてください
```

#### 4. 完了

2-3分でサイトが更新されます。

---

### カスタムパラメータ

#### スタック名を変更

```powershell
.\deploy-portfolio.ps1 -StackName "my-custom-portfolio"
```

#### 別のブランチからデプロイ

```powershell
.\deploy-portfolio.ps1 -Branch "develop"
```

#### 利用可能なパラメータ

| パラメータ | デフォルト値 | 説明 |
|-----------|------------|------|
| `-ApiToken` | `.env`から読み込み | Portainer APIトークン |
| `-PortainerUrl` | `http://192.168.0.95:9000` | Portainer URL |
| `-StackName` | `portfolio-site` | デプロイするスタック名 |
| `-RepoUrl` | `https://github.com/clamm0363/Portfolio-Page` | GitHubリポジトリURL |
| `-Branch` | `main` | デプロイするブランチ名 |

---

## スクリプトの詳細動作

### 処理フロー

```
1. 環境変数読み込み
   ↓ .env から必須変数をロード
   ↓ TUNNEL_TOKEN, POSTGRES_PASSWORD, UMAMI_HASH_SALT をチェック
   
2. Portainer 接続
   ↓ API トークンで認証
   ↓ Endpoint ID 取得 (通常は 3)
   
3. 既存スタック確認
   ↓ すべてのスタックを取得
   ↓ Swarm ID を既存の Swarm Stack から取得
   
4. 旧スタック削除（自動）
   ↓ portfolio-site-new が存在する場合は削除（ポート競合回避）
   ↓ portfolio-site が存在する場合は削除
   ↓ endpointId パラメータ付きで正しく削除
   ↓ 10秒待機（ポート解放）
   
5. 環境変数準備
   ↓ Portainer API 形式に変換
   ↓ [ { name: "POSTGRES_DB", value: "umami" }, ... ]
   
6. 新しいスタック作成
   ↓ API: /api/stacks/create/swarm/repository
   ↓ GitHub リポジトリから docker-compose.yml 取得
   ↓ 環境変数を注入
   ↓ Swarm Stack としてデプロイ
   
7. 完了
   ↓ Stack ID を表示
   ↓ アクセス URL を表示
```

### 重要な技術的詳細

#### 1. UTF-8エンコーディング設定

```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
```

日本語の文字化けを防止します。

#### 2. Swarm ID の動的取得

```powershell
$swarmStack = $stacks | Where-Object { $_.Type -eq 1 -and $_.SwarmId } | Select-Object -First 1
$swarmId = $swarmStack.SwarmId
```

既存の Swarm Stack から Swarm ID を自動取得します。

#### 3. endpointId を使った削除

```powershell
$deleteUrl = "$PortainerUrl/api/stacks/$stackId?endpointId=$endpointId"
Invoke-RestMethod -Uri $deleteUrl -Method Delete -Headers $headers
```

Portainer API の仕様に合わせて、削除時に `endpointId` パラメータを明示的に指定します。

#### 4. Portainer 2.x API エンドポイント

```powershell
$apiUrl = "$PortainerUrl/api/stacks/create/swarm/repository?endpointId=$endpointId"
```

Swarm Stack 作成には専用エンドポイントを使用します（従来の `type=2&method=repository` ではありません）。

#### 5. 自動削除機能

- **portfolio-site-new**: 旧スタック（ポート8001使用）を自動削除
- **portfolio-site**: 既存スタックがあれば削除して置き換え

---

## トラブルシューティング

### エラー: `.env file not found`

**原因**: `.env` ファイルが存在しない

**解決方法**:
```powershell
cp .env.example .env
# .env を編集して実際の値を設定
```

---

### エラー: `Missing required environment variables`

**原因**: 必須の環境変数が `.env` に設定されていない

**解決方法**:
`.env` ファイルを開いて、以下を確認：
- `TUNNEL_TOKEN`
- `POSTGRES_PASSWORD`
- `UMAMI_HASH_SALT`
- `PORTAINER_API_TOKEN`

---

### エラー: `リモート サーバーがエラーを返しました: (401) 権限がありません`

**原因**: Portainer APIトークンが無効

**解決方法**:
1. Portainer UI で新しいAPIトークンを作成
2. `.env` ファイルの `PORTAINER_API_TOKEN` を更新

---

### エラー: `リモート サーバーがエラーを返しました: (404) 見つかりません`

**原因**: Portainer URL が間違っている、またはPortainerが起動していない

**解決方法**:
1. ブラウザで http://192.168.0.95:9000 にアクセスできるか確認
2. `.env` の `PORTAINER_URL` が正しいか確認
3. Portainer が起動しているか確認: `docker ps | grep portainer`

---

### エラー: `No existing Swarm stack found to get Swarm ID`

**原因**: Portainer に Swarm Stack が1つも存在しない

**解決方法**:
1. Docker Swarm が初期化されているか確認: `docker node ls`
2. Portainer が Swarm クラスタに接続されているか確認
3. 最初のStackは Portainer UI から手動で作成する必要があります

---

### エラー: `port 'XXXX' is already in use`

**原因**: 別のサービスが同じポートを使用している

**解決方法**:
1. Portainer UI で競合しているStackを確認
2. 不要なStackを削除
3. スクリプトを再実行（自動削除機能が動作します）

---

### エラー: `Invalid Swarm ID`

**原因**: Swarm ID が正しく取得できていない

**解決方法**:
このエラーは最新版のスクリプトでは発生しません。スクリプトが最新版か確認してください。

---

### 文字化け（日本語が???になる）

**原因**: PowerShell のエンコーディング設定

**解決方法**:
スクリプトの先頭に以下が含まれているか確認：
```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
```

---

## セキュリティ

### ✅ 保護されているファイル

`.gitignore` により、以下のファイルは Git にコミットされません：

```
✓ .env                      (APIトークン、パスワード)
✓ portfolio-site-new.yml    (パスワード、トークン含む)
✓ *.yml.backup              (バックアップファイル)
```

### ❌ 絶対にコミットしてはいけない情報

- Portainer APIトークン (`ptr_...`)
- Cloudflare Tunnel Token (`eyJhIjoi...`)
- データベースパスワード
- Umami Hash Salt

### ✅ 安全にコミットできるファイル

- `deploy-portfolio.ps1` (スクリプト本体)
- `docker-compose.yml` (環境変数参照のみ)
- `.env.example` (テンプレート)
- ドキュメント (`DEPLOYMENT.md`, `README.md`, このファイル)

---

## 実行例

### 成功時の出力

```
ℹ Reading environment variables from .env...
ℹ Using PORTAINER_API_TOKEN from .env file
ℹ Portainer URL: http://192.168.0.95:9000

═══ Deploying Portfolio to Docker Swarm Stack ═══

ℹ Connecting to Portainer at http://192.168.0.95:9000...
ℹ Fetching endpoint ID...
✓ Endpoint ID: 3
ℹ Checking for existing stacks...
✓ Swarm ID obtained: ti90qwoi56zenc92pn51pdu12
ℹ Stack 'portfolio-site' already exists. Deleting...
✓ Existing stack deleted
ℹ Waiting for cleanup...
ℹ Preparing environment variables for Swarm Stack...
✓ Environment variables prepared: 5 variables
ℹ Creating new Swarm Stack 'portfolio-site'...
✓ Stack created successfully!
✓ Stack ID: 31

═══ Deployment Complete ═══

✓ Portfolio site deployment initiated!

ℹ Stack Name: portfolio-site
ℹ Repository: https://github.com/clamm0363/Portfolio-Page
ℹ Branch: main

ℹ Services deployed:
  • nginx (Swarm Service)
  • umami (Swarm Service)
  • umami-db (PostgreSQL)
  • cloudflared (Cloudflare Tunnel)

ℹ Your portfolio site will be accessible via:
  🌐 Public URL: https://clamm-translation.net (via Cloudflare Tunnel)
  📊 Umami:      http://<node-ip>:3002

ℹ To check deployment status, run:
  docker stack ps portfolio-site
  docker stack services portfolio-site
  docker service logs portfolio-site_nginx
  docker service logs portfolio-site_cloudflared

ℹ Next steps:
  1. Wait 2-3 minutes for all services to start
  2. Check service status: docker stack ps portfolio-site
  3. Access your site via Cloudflare Tunnel
  4. Configure Umami at http://<node-ip>:3002 (admin/umami)
```

---

## AIセッションでの使用方法

別のAIセッション（Cursor、Claude、ChatGPTなど）からこのドキュメントを参照してデプロイする場合：

### 1. このドキュメントを読む

AIに以下のように依頼：

```
DEPLOY_FROM_CURSOR.md を読んで、デプロイ方法を理解してください
```

### 2. 前提条件を確認

```
.env ファイルが存在し、必須の環境変数が設定されているか確認してください
```

### 3. デプロイを実行

```
deploy-portfolio.ps1 を実行して、portfolio サイトをデプロイしてください
```

### 4. 結果を確認

```
デプロイが成功したか確認してください。エラーがあればトラブルシューティングを実施してください。
```

---

## 関連ドキュメント

- **[DEPLOYMENT.md](./DEPLOYMENT.md)**: Docker Swarm クラスタの構築とインフラセットアップ
- **[README.md](./README.md)**: プロジェクト概要とクイックスタート
- **[.env.example](./.env.example)**: 環境変数のテンプレート

---

## 更新履歴

- **2026-02-04**: Docker Swarm + Portainer API 対応版に全面改訂
  - Swarm ID自動取得機能
  - endpointId修正による削除機能
  - UTF-8エンコーディング設定
  - portfolio-site-new自動削除
  - 最新の環境変数構成に対応

---

**このドキュメントに関する質問や問題があれば、GitHubのIssueで報告してください。**
