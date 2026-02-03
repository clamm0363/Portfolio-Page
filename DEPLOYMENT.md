# Docker Swarm デプロイガイド

このドキュメントは、Docker Swarm + CephFS 構成でポートフォリオサイトをデプロイするための詳細な手順をまとめています。

## 目次

1. [前提条件](#前提条件)
2. [インフラ構築](#インフラ構築)
3. [初回セットアップ](#初回セットアップ)
4. [Stack デプロイ](#stack-デプロイ)
5. [Portainer経由でのデプロイ（Cursor連携）](#portainer経由でのデプロイcursor連携)
6. [Cloudflare Tunnel 設定](#cloudflare-tunnel-設定)
7. [運用管理](#運用管理)
8. [トラブルシューティング](#トラブルシューティング)
9. [バックアップとリカバリ](#バックアップとリカバリ)

## 前提条件

### ハードウェア要件

- **ノード数**: 3台以上（高可用性のため）
- **CPU**: 各ノード 2コア以上
- **メモリ**: 各ノード 4GB以上
- **ストレージ**: 
  - ローカル: 20GB以上（Dockerイメージ用）
  - CephFS: 10GB以上（アプリケーションデータ用）

### ソフトウェア要件

- **OS**: Ubuntu 20.04 LTS / 22.04 LTS 推奨（他のLinuxディストリビューションも可）
- **Docker**: 20.10以降
- **Docker Compose**: v2.0以降（stackコマンド使用のため不要だが、開発時に便利）
- **Ceph クラスタ**: 既存のCephクラスタまたは新規構築

### ネットワーク要件

- 各ノード間の通信が可能であること
- ポート開放:
  - `2377/tcp`: Swarm クラスタ管理通信
  - `7946/tcp`, `7946/udp`: ノード間通信
  - `4789/udp`: overlay ネットワークトラフィック
  - `8001/tcp`: Nginx 公開ポート
  - `3002/tcp`: Umami 管理画面ポート

## インフラ構築

### 1. Docker Swarm クラスタの構築

#### マネージャーノードの初期化

マネージャーノードとなるサーバーで以下を実行：

```bash
# Swarmの初期化
docker swarm init --advertise-addr <マネージャーノードのIPアドレス>
```

実行すると、ワーカーノード追加用のコマンドが表示されます：

```bash
docker swarm join --token SWMTKN-1-xxxxx <マネージャーIP>:2377
```

#### ワーカーノードの追加

各ワーカーノードで、上記のコマンドを実行：

```bash
docker swarm join --token SWMTKN-1-xxxxx <マネージャーIP>:2377
```

#### クラスタの確認

マネージャーノードで確認：

```bash
# ノード一覧を表示
docker node ls

# 期待される出力例:
# ID              HOSTNAME   STATUS    AVAILABILITY   MANAGER STATUS
# abc123 *        docker01   Ready     Active         Leader
# def456          docker02   Ready     Active         
# ghi789          docker03   Ready     Active         
```

### 2. CephFS のマウント

#### 前提: Ceph クラスタが構築済み

Ceph クラスタの構築については、[Ceph公式ドキュメント](https://docs.ceph.com/)を参照してください。

#### 各ノードでの CephFS マウント

全ての Swarm ノード（マネージャー・ワーカー共に）で以下を実行：

```bash
# ceph-commonパッケージのインストール（Ubuntu/Debian）
sudo apt update
sudo apt install -y ceph-common

# マウントポイントの作成
sudo mkdir -p /mnt/cephfs

# CephFS のマウント
sudo mount -t ceph <monitor-ip>:6789:/ /mnt/cephfs \
  -o name=admin,secret=<ceph-admin-secret>

# マウントの確認
df -h | grep cephfs
```

#### 永続的なマウント設定

`/etc/fstab` に追加して、再起動後も自動マウントされるように設定：

```bash
# /etc/fstab に追記
<monitor-ip>:6789:/     /mnt/cephfs    ceph    name=admin,secret=<ceph-secret>,_netdev,noatime    0 0
```

または、systemd マウントユニットを使用：

```bash
# /etc/systemd/system/mnt-cephfs.mount
[Unit]
Description=CephFS Mount
After=network-online.target

[Mount]
What=<monitor-ip>:6789:/
Where=/mnt/cephfs
Type=ceph
Options=name=admin,secret=<secret>,_netdev,noatime

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable mnt-cephfs.mount
sudo systemctl start mnt-cephfs.mount
```

### 3. Overlay ネットワークの作成

マネージャーノードで実行：

```bash
# 外部ネットワーク 'public' を作成
docker network create \
  --driver overlay \
  --attachable \
  public

# ネットワークの確認
docker network ls | grep public
docker network inspect public
```

## 初回セットアップ

### 1. リポジトリのクローン

マネージャーノードで実行：

```bash
cd ~
git clone https://github.com/clamm0363/Portfolio-Page.git
cd Portfolio-Page
```

### 2. CephFS 上のディレクトリ構造作成

```bash
# ディレクトリ作成
sudo mkdir -p /mnt/cephfs/portfolio/html/assets/css
sudo mkdir -p /mnt/cephfs/portfolio/html/assets/images
sudo mkdir -p /mnt/cephfs/portfolio/html/nginx
sudo mkdir -p /mnt/cephfs/portfolio/db

# 静的ファイルのコピー
sudo cp index.html /mnt/cephfs/portfolio/html/
sudo cp -r assets/css/* /mnt/cephfs/portfolio/html/assets/css/
sudo cp -r assets/images/* /mnt/cephfs/portfolio/html/assets/images/
sudo cp nginx/nginx.conf /mnt/cephfs/portfolio/html/nginx/

# 権限設定
# PostgreSQL は UID 999 で実行されるため
sudo chown -R 999:999 /mnt/cephfs/portfolio/db

# その他のファイルは読み取り専用でマウントするため、適切な権限を設定
sudo chmod -R 755 /mnt/cephfs/portfolio/html
```

### 3. 環境変数の設定

```bash
# .env ファイルの作成
cp .env.example .env

# エディタで編集
nano .env
```

`.env` ファイルに以下を設定：

```bash
# Cloudflare Tunnel Token
# Zero Trust ダッシュボードで取得したトークン
TUNNEL_TOKEN=eyJhIjoixxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# Database Configuration
POSTGRES_DB=umami
POSTGRES_USER=umami
POSTGRES_PASSWORD=YourStrongPasswordHere123!

# Umami Hash Salt
# 以下のコマンドで生成: openssl rand -hex 32
UMAMI_HASH_SALT=a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0e1f2
```

**セキュリティ注意:**
- `.env` ファイルは `.gitignore` に含まれており、Gitにコミットされません
- パスワードは複雑なものを使用してください
- 本番環境では Docker secrets の使用も検討してください

## Stack デプロイ

### 1. 環境変数の読み込みとデプロイ

マネージャーノードで実行：

```bash
# 環境変数をエクスポート（stack deployは.envを自動読み込みしない）
export $(cat .env | grep -v '^#' | xargs)

# Stack のデプロイ
docker stack deploy -c docker-compose.yml portfolio
```

### 2. デプロイの確認

```bash
# Stack のサービス一覧
docker stack services portfolio

# 期待される出力:
# ID        NAME                    MODE        REPLICAS   IMAGE
# xxx       portfolio_nginx         replicated  1/1        nginx:alpine
# yyy       portfolio_umami         replicated  1/1        ghcr.io/umami-software/umami:...
# zzz       portfolio_umami-db      replicated  1/1        postgres:15-alpine
# www       portfolio_cloudflared   replicated  1/1        cloudflare/cloudflared:latest

# 各タスク（コンテナ）の状態を確認
docker stack ps portfolio

# サービスのログを確認
docker service logs portfolio_nginx
docker service logs portfolio_umami
docker service logs portfolio_umami-db
docker service logs portfolio_cloudflared
```

### 3. サービスの動作確認

```bash
# Nginx の動作確認（任意のノードのIPアドレスで）
curl http://<任意のノードIP>:8001

# Umami 管理画面へのアクセス
curl http://<任意のノードIP>:3002
```

ブラウザでアクセス：
- ポートフォリオサイト: `http://<ノードIP>:8001`
- Umami 管理画面: `http://<ノードIP>:3002`

## Portainer経由でのデプロイ（Cursor連携）

Portainerを使用すると、Cursorから直接デプロイを自動化できます。これにより、コードを更新するたびに手動でSSH接続してコマンドを実行する必要がなくなります。

### 前提条件

- Portainerがインストール済みであること
- Portainerが Swarm クラスタに接続されていること
- GitHubリポジトリがPortainerからアクセス可能であること（パブリックまたはPAT認証）

### 方法A: Portainer API経由（推奨 - 完全自動化）

#### 1. Portainer APIトークンの取得

1. **Portainer UIにログイン**
   - ブラウザで Portainer にアクセス（例: `http://192.168.0.95:9000`）

2. **API keyを作成**
   - 右上のユーザーアイコンをクリック
   - **My account** を選択
   - **API keys** セクションまでスクロール
   - **+ Add API key** をクリック
   - Description: `Cursor Deployment` と入力
   - **Add API key** をクリック
   - 表示されたトークンをコピー（`ptr_` で始まる文字列）

3. **.env ファイルに設定**
   ```bash
   # .env ファイルに追記
   PORTAINER_API_TOKEN=ptr_your_copied_token_here
   PORTAINER_URL=http://192.168.0.95:9000
   ```

#### 2. Cursorからデプロイ

1. **ファイルを編集**
   - Cursorで `index.html` やその他のファイルを編集

2. **Git commit & push**
   ```bash
   git add .
   git commit -m "Update: サイト内容の更新"
   git push origin main
   ```

3. **PowerShellで自動デプロイ**
   ```powershell
   # Cursor のターミナル（PowerShell）で実行
   .\deploy-portfolio.ps1
   ```
   
   スクリプトは `.env` から自動的にAPIトークンと環境変数を読み取ります。

4. **デプロイ確認**
   - スクリプトの出力でデプロイステータスを確認
   - または Portainer UI で確認

#### 3. 更新フロー（日常的な運用）

```
1. Cursor: ファイルを編集（index.html など）
2. Cursor: git commit & push
3. Cursor ターミナル: .\deploy-portfolio.ps1
   ↓
完了！サイトが自動更新されます（2-3分）
```

### 方法B: Portainer UI経由（手動）

Portainer UIから手動でデプロイする場合：

#### 初回Stack作成

1. **Portainer UIにアクセス**
   - ブラウザで `http://192.168.0.95:9000` を開く

2. **Stacksページへ移動**
   - 左メニューから **Stacks** を選択
   - **+ Add stack** ボタンをクリック

3. **Git Repository設定**
   - **Build method**: **Repository** を選択
   - **Repository URL**: `https://github.com/clamm0363/Portfolio-Page`
   - **Repository reference**: `refs/heads/main`
   - **Compose path**: `docker-compose.yml`
   - **Authentication**: プライベートリポジトリの場合のみチェック

4. **環境変数を設定**
   - **Environment variables** セクションで以下を追加：
   ```
   TUNNEL_TOKEN=your-cloudflare-tunnel-token
   POSTGRES_DB=umami
   POSTGRES_USER=umami
   POSTGRES_PASSWORD=your-strong-password
   UMAMI_HASH_SALT=your-64-char-hex-string
   ```

5. **Stackをデプロイ**
   - Stack name: `portfolio`
   - **Deploy the stack** ボタンをクリック

#### 既存Stackの更新

1. **Stacks** ページで `portfolio` Stackを選択
2. **Pull and redeploy** ボタンをクリック
   - GitHubから最新のコードを取得して再デプロイされます

### トラブルシューティング（Portainerデプロイ）

#### APIトークンエラー

```powershell
# エラー: API Token is required
```

**解決方法:**
- `.env` ファイルに `PORTAINER_API_TOKEN` が設定されているか確認
- トークンが有効か確認（Portainer UI → My account → API keys）

#### 環境変数エラー

```powershell
# エラー: Missing required environment variables
```

**解決方法:**
- `.env` ファイルに以下が設定されているか確認：
  - `TUNNEL_TOKEN`
  - `POSTGRES_PASSWORD`
  - `UMAMI_HASH_SALT`

#### Stack作成失敗

```
# エラー: Stack creation failed
```

**解決方法:**
1. Portainer UIで Stack の詳細を確認
2. GitHubリポジトリがアクセス可能か確認
3. `docker-compose.yml` の構文エラーをチェック
4. `public` ネットワークが存在するか確認：
   ```bash
   docker network ls | grep public
   ```

#### Swarm関連エラー

```
# エラー: Endpoint not found or not a Swarm manager
```

**解決方法:**
1. Docker Swarm が初期化されているか確認：
   ```bash
   docker node ls
   ```
2. Portainer が正しいエンドポイントに接続されているか確認

### セキュリティ上の注意

1. **APIトークンの管理**
   - `.env` ファイルは絶対にGitにコミットしない（`.gitignore`で除外済み）
   - APIトークンを定期的にローテーション
   - 不要になったトークンは削除

2. **Portainer UIのセキュリティ**
   - 強力な管理者パスワードを使用
   - 可能であればPortainerをVPN経由でのみアクセス可能にする
   - SSL証明書を正式なものに変更（自己署名証明書を使用している場合）

## Cloudflare Tunnel 設定

### 1. Cloudflare Zero Trust でトンネル作成

1. **Cloudflare ダッシュボードにアクセス**
   - https://one.dash.cloudflare.com/ にログイン

2. **トンネルの作成**
   - 左メニュー: **Networks** → **Tunnels**
   - **Create a tunnel** をクリック
   - **Cloudflared** を選択
   - トンネル名を入力（例: `portfolio-swarm`）
   - **Save tunnel** をクリック

3. **トークンの取得**
   - トンネル作成後、トークンが表示されます
   - トークンをコピーして `.env` ファイルの `TUNNEL_TOKEN` に設定
   - すでにデプロイ済みの場合は、サービスを更新：
     ```bash
     export TUNNEL_TOKEN=your-new-token
     docker service update --env-add TUNNEL_TOKEN=${TUNNEL_TOKEN} portfolio_cloudflared
     ```

### 2. Public Hostname の設定

1. **ルーティング設定**
   - トンネルの詳細ページで **Public Hostname** タブをクリック
   - **Add a public hostname** をクリック

2. **ホスト名とサービスの設定**
   - **Subdomain**: 空欄（ルートドメインの場合）または `www` など
   - **Domain**: `clamm-translation.net`（ドロップダウンから選択）
   - **Path**: 空欄
   - **Service**: 以下を設定
     - Type: `HTTP`
     - URL: `nginx:80`（Swarm内部のサービス名とポート）
   - **Save hostname** をクリック

### 3. DNS 設定の確認

Cloudflare が自動的に DNS レコードを作成します：

1. Cloudflare ダッシュボードで **DNS** → **Records** を確認
2. 以下のレコードが存在することを確認：
   - Type: `CNAME`
   - Name: `@` または設定したサブドメイン
   - Target: `<tunnel-id>.cfargotunnel.com`
   - Proxy status: **Proxied**（オレンジの雲）

### 4. SSL/TLS 設定

1. **SSL/TLS 暗号化モード**
   - Cloudflare ダッシュボード → **SSL/TLS** → **Overview**
   - 暗号化モード: **Full** または **Flexible** を選択
     - **Flexible**: オリジン（Nginx）への通信はHTTP（今回の構成）
     - **Full**: オリジンへの通信もHTTPSが必要

## 運用管理

### サービスのスケーリング

```bash
# Nginx のレプリカを3つに増やす
docker service scale portfolio_nginx=3

# Umami のレプリカを2つに増やす
docker service scale portfolio_umami=2

# スケーリング結果の確認
docker service ls
```

**注意:** 
- `umami-db` は単一レプリカで運用してください（PostgreSQLのレプリケーションは別途設定が必要）
- `cloudflared` も単一レプリカで十分です

### ローリングアップデート

静的ファイルを更新した場合：

```bash
# CephFS上のファイルを更新
sudo cp index.html /mnt/cephfs/portfolio/html/

# Nginxサービスを強制更新（キャッシュクリア）
docker service update --force portfolio_nginx
```

イメージを更新する場合：

```bash
# 新しいイメージをpull
docker service update --image nginx:1.25-alpine portfolio_nginx

# ローリングアップデート設定を追加
docker service update \
  --update-parallelism 1 \
  --update-delay 10s \
  portfolio_nginx
```

### 環境変数の更新

```bash
# 環境変数を追加
docker service update --env-add NEW_VAR=value portfolio_umami

# 環境変数を削除
docker service update --env-rm OLD_VAR portfolio_umami

# 複数の環境変数を一度に更新
docker service update \
  --env-add VAR1=value1 \
  --env-add VAR2=value2 \
  portfolio_umami
```

### ログの確認と管理

```bash
# リアルタイムでログを表示
docker service logs -f portfolio_nginx

# 過去のログを表示（最新100行）
docker service logs --tail 100 portfolio_umami

# タイムスタンプ付きでログを表示
docker service logs -t portfolio_umami-db

# 特定のタスクのログを表示
docker service ps portfolio_nginx  # タスクIDを確認
docker logs <タスクID>
```

### サービスの再起動

```bash
# サービス全体を再起動（強制更新）
docker service update --force portfolio_nginx

# Stack全体を再デプロイ
docker stack rm portfolio
# 数秒待機してから
export $(cat .env | grep -v '^#' | xargs)
docker stack deploy -c docker-compose.yml portfolio
```

## トラブルシューティング

### サービスが起動しない

```bash
# サービスの詳細状態を確認
docker service ps portfolio_nginx --no-trunc

# エラーが表示される場合、そのエラーを確認
docker service logs portfolio_nginx

# タスクの詳細を確認
docker inspect <タスクID>
```

**一般的な原因:**
- CephFS のマウント失敗 → 全ノードでマウントを確認
- ネットワーク問題 → `public` ネットワークの存在を確認
- 環境変数の欠落 → `.env` ファイルを確認

### CephFS マウントの問題

```bash
# 各ノードでマウント状態を確認
mount | grep cephfs

# マウントされていない場合、再マウント
sudo mount -t ceph <monitor-ip>:6789:/ /mnt/cephfs \
  -o name=admin,secret=<secret>

# Ceph クラスタの健全性を確認
ceph -s
```

### ネットワーク接続の問題

```bash
# overlay ネットワークの確認
docker network inspect public

# サービス間の通信テスト
docker exec $(docker ps -q -f name=portfolio_nginx) ping umami-db

# DNSの確認
docker exec $(docker ps -q -f name=portfolio_nginx) nslookup umami
```

### データベース接続エラー

```bash
# PostgreSQL のログを確認
docker service logs portfolio_umami-db

# データベースコンテナに接続して確認
docker exec -it $(docker ps -q -f name=portfolio_umami-db) psql -U umami

# 接続情報の確認
docker service inspect portfolio_umami --pretty | grep -A 10 "Env"
```

**よくある問題:**
- パスワード不一致 → `.env` ファイルを確認
- データベースが起動していない → ヘルスチェックを確認
- CephFS の権限問題 → `chown 999:999` を確認

### Cloudflare Tunnel の問題

```bash
# cloudflared のログを確認
docker service logs portfolio_cloudflared

# トークンの確認
docker service inspect portfolio_cloudflared --pretty | grep TUNNEL_TOKEN

# 接続テスト
docker exec $(docker ps -q -f name=portfolio_cloudflared) cloudflared tunnel info
```

## バックアップとリカバリ

### データベースのバックアップ

#### SQL ダンプによるバックアップ

```bash
# PostgreSQL ダンプの作成
docker exec $(docker ps -q -f name=portfolio_umami-db) \
  pg_dump -U umami umami > backup-$(date +%Y%m%d-%H%M%S).sql

# 圧縮バックアップ
docker exec $(docker ps -q -f name=portfolio_umami-db) \
  pg_dump -U umami umami | gzip > backup-$(date +%Y%m%d-%H%M%S).sql.gz
```

#### CephFS データディレクトリのバックアップ

```bash
# データベースファイル全体をバックアップ
sudo tar -czf portfolio-db-backup-$(date +%Y%m%d).tar.gz \
  /mnt/cephfs/portfolio/db

# 別のCephFSディレクトリにコピー
sudo cp -a /mnt/cephfs/portfolio/db /mnt/cephfs/backups/portfolio-db-$(date +%Y%m%d)
```

### 自動バックアップの設定

cron ジョブでの定期バックアップ：

```bash
# /etc/cron.daily/portfolio-backup.sh
#!/bin/bash
BACKUP_DIR="/mnt/cephfs/backups"
DATE=$(date +%Y%m%d-%H%M%S)

# データベースダンプ
docker exec $(docker ps -q -f name=portfolio_umami-db) \
  pg_dump -U umami umami | gzip > ${BACKUP_DIR}/portfolio-${DATE}.sql.gz

# 古いバックアップを削除（30日以上前）
find ${BACKUP_DIR} -name "portfolio-*.sql.gz" -mtime +30 -delete
```

```bash
# スクリプトを実行可能にする
sudo chmod +x /etc/cron.daily/portfolio-backup.sh
```

### データベースの復元

```bash
# SQL ダンプから復元
cat backup.sql | docker exec -i $(docker ps -q -f name=portfolio_umami-db) \
  psql -U umami umami

# 圧縮ファイルから復元
gunzip -c backup.sql.gz | docker exec -i $(docker ps -q -f name=portfolio_umami-db) \
  psql -U umami umami
```

#### 完全リカバリ手順

1. **Stack の停止**
   ```bash
   docker stack rm portfolio
   ```

2. **データベースディレクトリのクリア**
   ```bash
   sudo rm -rf /mnt/cephfs/portfolio/db/*
   ```

3. **バックアップの復元**
   ```bash
   sudo tar -xzf portfolio-db-backup-YYYYMMDD.tar.gz -C /
   ```

4. **Stack の再デプロイ**
   ```bash
   export $(cat .env | grep -v '^#' | xargs)
   docker stack deploy -c docker-compose.yml portfolio
   ```

## セキュリティのベストプラクティス

### Docker Secrets の使用

本番環境では、環境変数の代わりに Docker secrets を使用することを推奨：

```bash
# secret の作成
echo "your-strong-password" | docker secret create postgres_password -
echo "your-tunnel-token" | docker secret create tunnel_token -

# docker-compose.yml で secrets を参照
# services:
#   umami-db:
#     secrets:
#       - postgres_password
#     environment:
#       POSTGRES_PASSWORD_FILE: /run/secrets/postgres_password
```

### ファイアウォール設定

```bash
# UFW の設定例（Ubuntu）
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 2377/tcp  # Swarm management
sudo ufw allow 7946      # Swarm node communication
sudo ufw allow 4789/udp  # Overlay network
sudo ufw allow 8001/tcp  # Nginx（必要な場合）
sudo ufw enable
```

### 定期的なセキュリティアップデート

```bash
# イメージの定期更新
docker service update --image nginx:alpine portfolio_nginx
docker service update --image postgres:15-alpine portfolio_umami-db
docker service update --image ghcr.io/umami-software/umami:postgresql-latest portfolio_umami
```

## まとめ

この構成により、以下が実現されます：

- **高可用性**: 複数ノードでのサービス冗長化
- **スケーラビリティ**: レプリカ数の動的調整
- **共有ストレージ**: CephFS による統一されたストレージ
- **自動フェイルオーバー**: ノード障害時の自動復旧
- **セキュアな公開**: Cloudflare Tunnel による保護

継続的な監視とメンテナンスを行い、安定したサービス提供を実現してください。
