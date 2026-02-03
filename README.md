# Portfolio Page

ゲーム翻訳者（Masaru Funahashi）のポートフォリオサイト

## 概要

このプロジェクトは、静的HTML + Tailwind CSSで構築されたポートフォリオサイトです。
Docker Swarm + CephFS による高可用性構成で、Nginx + Umami（アクセス解析）を使用して公開します。

## 技術スタック

- **フロントエンド**: HTML5 + Tailwind CSS（CDN経由）
- **Webサーバー**: Nginx（Swarm Serviceとして実行）
- **アクセス解析**: Umami（セルフホスト型）
- **データベース**: PostgreSQL（Umami用、CephFSで永続化）
- **オーケストレーション**: Docker Swarm（3ノードクラスタ）
- **ストレージ**: CephFS（分散ファイルシステム）
- **公開**: Cloudflare Tunnel（コンテナ内で実行）

## アーキテクチャ

```
[Cloudflare Tunnel Container]
         ↓
   [Nginx Service]
         ↓
   [Umami Service]
         ↓
[PostgreSQL Service]
         ↓
   [CephFS Storage]
```

## プロジェクト構造

```
portfolio/
├── index.html              # メインのポートフォリオページ
├── assets/
│   ├── css/               # カスタムCSS（必要に応じて）
│   └── images/            # 画像ファイル（必要に応じて）
├── docker-compose.yml      # Docker Stack設定（Swarm用）
├── nginx/
│   └── nginx.conf         # Nginx設定ファイル
├── .env.example           # 環境変数テンプレート
├── .gitignore
├── README.md
└── DEPLOYMENT.md          # 詳細なデプロイガイド
```

## 前提条件

このプロジェクトをデプロイするには、以下の環境が必要です：

### 1. Docker Swarm クラスタ

3ノード以上の Docker Swarm クラスタが構築されていること。

```bash
# マネージャーノードで初期化
docker swarm init --advertise-addr <マネージャーIPアドレス>

# ワーカーノードを追加（マネージャーノードで表示されたコマンドを実行）
docker swarm join --token <トークン> <マネージャーIPアドレス>:2377
```

### 2. CephFS マウント

全ノードで CephFS が `/mnt/cephfs` にマウントされていること。

```bash
# 各ノードで実行
sudo mount -t ceph <monitor-ip>:6789:/ /mnt/cephfs -o name=admin,secret=<ceph-secret>

# 永続化（/etc/fstabに追加）
<monitor-ip>:6789:/     /mnt/cephfs    ceph    name=admin,secret=<ceph-secret>,_netdev    0 0
```

### 3. Overlay ネットワーク

外部 overlay ネットワーク `public` が作成されていること。

```bash
# マネージャーノードで実行
docker network create --driver overlay --attachable public
```

### 4. Cloudflare アカウント

Cloudflare Zero Trust でトンネルを作成し、トークンを取得していること。

## セットアップ手順

### 1. リポジトリのクローン

```bash
git clone https://github.com/clamm0363/Portfolio-Page.git
cd Portfolio-Page
```

### 2. CephFS 上のディレクトリ構造準備

```bash
# CephFS上に必要なディレクトリを作成
sudo mkdir -p /mnt/cephfs/portfolio/html/assets/css
sudo mkdir -p /mnt/cephfs/portfolio/html/assets/images
sudo mkdir -p /mnt/cephfs/portfolio/html/nginx
sudo mkdir -p /mnt/cephfs/portfolio/db

# 静的ファイルをCephFSにコピー
sudo cp index.html /mnt/cephfs/portfolio/html/
sudo cp -r assets/* /mnt/cephfs/portfolio/html/assets/
sudo cp nginx/nginx.conf /mnt/cephfs/portfolio/html/nginx/

# 適切な権限を設定
sudo chown -R 999:999 /mnt/cephfs/portfolio/db  # PostgreSQLユーザー
```

### 3. 環境変数の設定

```bash
cp .env.example .env
```

`.env`ファイルを編集し、以下の値を設定してください：

```bash
# Cloudflare Tunnel Token
TUNNEL_TOKEN=your-cloudflare-tunnel-token-here

# Database Configuration
POSTGRES_DB=umami
POSTGRES_USER=umami
POSTGRES_PASSWORD=your-strong-password-here

# Umami Hash Salt (generate with: openssl rand -hex 32)
UMAMI_HASH_SALT=your-random-64-character-hex-string-here
```

### 4. Stack のデプロイ

```bash
# 環境変数を読み込んでデプロイ
docker stack deploy -c docker-compose.yml portfolio
```

### 5. デプロイの確認

```bash
# サービスの状態を確認
docker stack ps portfolio

# サービスのログを確認
docker service logs portfolio_nginx
docker service logs portfolio_umami
docker service logs portfolio_umami-db
docker service logs portfolio_cloudflared
```

ブラウザで Cloudflare Tunnel 経由でアクセスして確認してください。

## Cloudflare Tunnel 設定

### トンネルの作成

1. **Cloudflare ダッシュボードにアクセス**
   - [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) にログイン

2. **トンネルを作成**
   - Networks → Tunnels → Create a tunnel
   - トンネル名を入力（例: `portfolio-swarm`）
   - トークンをコピー（`.env` の `TUNNEL_TOKEN` に設定）

3. **Public Hostname を設定**
   - Public Hostname タブで以下を設定：
     - Subdomain/Domain: `clamm-translation.net`
     - Service: `http://nginx:80`（Swarm内部サービス名）
   - Save hostname

4. **DNS 設定を確認**
   - Cloudflare DNS に CNAME レコードが自動作成されます
   - Type: `CNAME`
   - Name: `@` または サブドメイン
   - Target: `<tunnel-id>.cfargotunnel.com`

## Umami 設定

### 初回セットアップ

1. **Umami 管理画面にアクセス**
   - URL: `http://<任意のノードIP>:3002`
   - デフォルトログイン:
     - Username: `admin`
     - Password: `umami`

2. **管理者パスワードを変更**
   - Settings → Profile → Change Password

3. **サイトを追加**
   - Settings → Websites → Add website
   - Name: `Portfolio`
   - Domain: `clamm-translation.net`

4. **トラッキングコードを取得**
   - 作成したウェブサイトの「Edit」→「Tracking code」をクリック
   - 表示されたスクリプトタグをコピー

5. **index.html にトラッキングコードを追加**
   - CephFS上の `/mnt/cephfs/portfolio/html/index.html` を編集
   - `<head>` セクション内にスクリプトタグを追加

   ```html
   <script async src="http://<ノードIP>:3002/script.js" data-website-id="your-website-id"></script>
   ```

## 運用管理

### サービスのスケーリング

```bash
# Nginxのレプリカ数を増やす
docker service scale portfolio_nginx=3

# Umamiのレプリカ数を増やす
docker service scale portfolio_umami=2
```

### サービスの更新

```bash
# 静的ファイルを更新した場合
sudo cp index.html /mnt/cephfs/portfolio/html/
docker service update --force portfolio_nginx

# 環境変数を更新した場合
docker service update --env-add NEW_VAR=value portfolio_umami
```

### ログの確認

```bash
# すべてのサービスのログ
docker stack services portfolio

# 特定のサービスのログ
docker service logs -f portfolio_nginx
docker service logs -f portfolio_umami

# 特定のタスク（コンテナ）のログ
docker service ps portfolio_nginx
docker logs <タスクID>
```

### データベースのバックアップ

```bash
# PostgreSQLデータベースのバックアップ
docker exec $(docker ps -q -f name=portfolio_umami-db) pg_dump -U umami umami > backup.sql

# CephFS上のデータベースファイルを直接バックアップ
sudo tar -czf portfolio-db-backup-$(date +%Y%m%d).tar.gz /mnt/cephfs/portfolio/db
```

### データベースの復元

```bash
# バックアップから復元
cat backup.sql | docker exec -i $(docker ps -q -f name=portfolio_umami-db) psql -U umami umami
```

### Stack の停止と削除

```bash
# Stackを停止（削除）
docker stack rm portfolio

# データは CephFS 上に残るため、再デプロイで復元可能
docker stack deploy -c docker-compose.yml portfolio
```

## トラブルシューティング

### サービスが起動しない

```bash
# サービスの詳細状態を確認
docker service ps portfolio_nginx --no-trunc

# エラーログを確認
docker service logs portfolio_nginx
```

### CephFS マウントの問題

```bash
# CephFS のマウント状態を確認
mount | grep cephfs

# 再マウント
sudo umount /mnt/cephfs
sudo mount -t ceph <monitor-ip>:6789:/ /mnt/cephfs -o name=admin,secret=<secret>
```

### ネットワークの問題

```bash
# overlay ネットワークの確認
docker network ls
docker network inspect public

# サービスのネットワーク接続を確認
docker exec $(docker ps -q -f name=portfolio_nginx) ping umami-db
```

### データベース接続エラー

1. 環境変数が正しく設定されているか確認
2. `umami-db` サービスが起動しているか確認
3. ヘルスチェックが成功しているか確認

```bash
docker service ps portfolio_umami-db
docker service logs portfolio_umami-db
```

### Cloudflare Tunnel の問題

```bash
# cloudflared サービスのログを確認
docker service logs portfolio_cloudflared

# トークンが正しく設定されているか確認
docker service inspect portfolio_cloudflared --pretty
```

## 高可用性について

この構成では以下の高可用性機能を提供します：

- **ノード障害時の自動フェイルオーバー**: Swarm が自動的に他のノードでサービスを再起動
- **負荷分散**: Ingress モードでトラフィックを複数レプリカに分散
- **ローリングアップデート**: サービスを停止せずに更新可能
- **共有ストレージ**: CephFS により全ノードでデータを共有

## 詳細なデプロイ手順

より詳細なデプロイ手順、インフラ構築方法、トラブルシューティングについては、[DEPLOYMENT.md](./DEPLOYMENT.md) を参照してください。

## ライセンス

このプロジェクトは個人のポートフォリオサイトです。

## 連絡先

- Note: https://note.com/clamm0363
