# Portfolio Page

ゲーム翻訳者（Masaru Funahashi）のポートフォリオサイト

## 概要

このプロジェクトは、静的HTML + Tailwind CSSで構築されたポートフォリオサイトです。
Docker環境でNginx + Umami（アクセス解析）を使用して公開します。

## 技術スタック

- **フロントエンド**: HTML5 + Tailwind CSS（CDN経由）
- **Webサーバー**: Nginx（Dockerコンテナ）
- **アクセス解析**: Umami（セルフホスト型）
- **データベース**: PostgreSQL（Umami用）
- **公開**: Cloudflare Tunnel

## プロジェクト構造

```
portfolio/
├── index.html              # メインのポートフォリオページ
├── assets/
│   ├── css/               # カスタムCSS（必要に応じて）
│   └── images/            # 画像ファイル（必要に応じて）
├── docker-compose.yml      # Docker Compose設定
├── nginx/
│   └── nginx.conf         # Nginx設定ファイル
├── .env.example           # 環境変数テンプレート
├── .gitignore
└── README.md
```

## セットアップ手順

### 1. リポジトリのクローン

```bash
git clone https://github.com/clamm0363/Portfolio-Page.git
cd Portfolio-Page
```

### 2. 環境変数の設定

```bash
cp .env.example .env
```

`.env`ファイルを編集し、以下の値を変更してください：

- `UMAMI_DB_PASSWORD`: 強力なパスワードに変更
- `UMAMI_HASH_SALT`: ランダムな文字列に変更（例: `openssl rand -hex 32`）

### 3. ローカルでの動作確認

```bash
docker-compose up -d
```

ブラウザで `http://localhost` にアクセスして確認してください。

Umamiの管理画面は `http://localhost:3002` でアクセスできます。
初回起動時は、Umamiの管理画面で管理者アカウントを作成してください。

### 4. コンテナの停止

```bash
docker-compose down
```

データを保持したまま停止する場合：

```bash
docker-compose stop
```

## デプロイ手順

### Dockerホスト（192.168.0.94）へのデプロイ

1. **プロジェクトファイルの転送**

   ```bash
   # SCPやrsyncなどでファイルを転送
   scp -r . user@192.168.0.94:/root/portfolio/
   ```

2. **Dockerホストでの起動**

   ```bash
   ssh user@192.168.0.94
   cd /root/portfolio
   cp .env.example .env
   # .envファイルを編集
   docker-compose up -d
   ```

3. **内部ネットワークでの確認**

   `http://192.168.0.94` でアクセスできることを確認してください。

### Cloudflare Tunnel設定

1. **CloudflareダッシュボードでTunnel作成**

   - Cloudflareダッシュボードにログイン
   - Zero Trust → Networks → Tunnels
   - 「Create a tunnel」をクリック
   - 「Cloudflared」を選択
   - トンネル名を入力（例: `portfolio-tunnel`）

2. **トンネルのインストールと設定**

   Dockerホスト（192.168.0.94）でcloudflaredをインストール：

   ```bash
   # Linuxの場合
   wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
   chmod +x cloudflared-linux-amd64
   sudo mv cloudflared-linux-amd64 /usr/local/bin/cloudflared
   ```

3. **トンネルの認証**

   ```bash
   cloudflared tunnel login
   ```

4. **トンネルの実行**

   ```bash
   cloudflared tunnel run <tunnel-name>
   ```

   または、systemdサービスとして設定：

   ```bash
   sudo cloudflared service install
   sudo systemctl start cloudflared
   sudo systemctl enable cloudflared
   ```

5. **ルーティング設定**

   Cloudflareダッシュボードで：
   - Public Hostname: `clamm-translation.net`
   - Service: `http://localhost:80`
   - または、Nginx Proxy Manager経由の場合: `http://192.168.0.110:80`

### DNS設定

1. CloudflareダッシュボードでDNS設定：
   - Type: `CNAME`
   - Name: `@` または `www`
   - Target: `<tunnel-id>.cfargotunnel.com`
   - Proxy status: Proxied（オレンジの雲）

2. SSL/TLS設定：
   - SSL/TLS encryption mode: `Full` または `Full (strict)`

## Umami設定

### 初回セットアップ

1. Umami管理画面にアクセス: `http://localhost:3002`（ローカル）または `http://192.168.0.94:3002`（デプロイ後）

2. 管理者アカウントを作成

3. サイトを追加:
   - Website Name: `Portfolio`
   - Domain: `clamm-translation.net`

4. トラッキングコードを取得

5. `index.html`の`<head>`セクションにトラッキングコードを追加:

   ```html
   <script async src="https://your-umami-instance.com/script.js" data-website-id="your-website-id"></script>
   ```

   **注意**: UmamiをCloudflare Tunnel経由で公開する場合、別途Tunnel設定が必要です。

## メンテナンス

### ログの確認

```bash
# すべてのコンテナのログ
docker-compose logs

# 特定のコンテナのログ
docker-compose logs nginx
docker-compose logs umami
```

### コンテナの再起動

```bash
docker-compose restart
```

### データベースのバックアップ

```bash
docker-compose exec umami-db pg_dump -U umami umami > backup.sql
```

### データベースの復元

```bash
docker-compose exec -T umami-db psql -U umami umami < backup.sql
```

## トラブルシューティング

### ポートが既に使用されている場合

`docker-compose.yml`のポート番号を変更してください：

```yaml
ports:
  - "8080:80"  # 80の代わりに8080を使用
```

### Umamiが起動しない場合

1. データベースのヘルスチェックを確認:
   ```bash
   docker-compose ps
   ```

2. Umamiのログを確認:
   ```bash
   docker-compose logs umami
   ```

3. データベース接続情報を確認（`.env`ファイル）

### Nginxが静的ファイルを配信しない場合

1. ボリュームマウントを確認:
   ```bash
   docker-compose exec nginx ls -la /usr/share/nginx/html
   ```

2. Nginx設定ファイルの構文チェック:
   ```bash
   docker-compose exec nginx nginx -t
   ```

## ライセンス

このプロジェクトは個人のポートフォリオサイトです。

## 連絡先

- Note: https://note.com/clamm0363
- Email: （連絡先情報を追加してください）
