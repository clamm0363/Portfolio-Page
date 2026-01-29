# Portainerデプロイガイド

このドキュメントは、Portainerでこのポートフォリオサイトをデプロイするための手順をまとめています。

## 前提条件

- Dockerがインストール済みのサーバー
- Portainerがセットアップ済み
- GitHubリポジトリへのアクセス（パブリックまたはPAT認証）

## デプロイ手順

### 1. 環境変数の準備

デプロイ前に、以下の環境変数を用意してください：

```bash
# Umami Database Configuration
UMAMI_DB_NAME=umami
UMAMI_DB_USER=umami
UMAMI_DB_PASSWORD=<強力なパスワード>

# Umami Hash Salt (generate with: openssl rand -hex 32)
UMAMI_HASH_SALT=<64文字のランダムな16進数文字列>

# PostgreSQL Configuration
POSTGRES_DB=umami
POSTGRES_USER=umami
POSTGRES_PASSWORD=<UMAMI_DB_PASSWORDと同じ値>
```

### 2. Portainerでのスタック作成

#### 2.1 Portainerにアクセス

ブラウザでPortainerの管理画面を開きます（例: `https://portainer.example.com`）

#### 2.2 新規スタックの作成

1. 左メニューから **Stacks** を選択
2. **+ Add stack** ボタンをクリック

#### 2.3 Git Repositoryから構築

**Build method** で以下を選択：
- ⭕ **Repository** を選択

**Repository configuration:**

| 項目 | 設定値 |
|------|--------|
| Authentication | （パブリックリポジトリの場合は不要） |
| Git repository URL | `https://github.com/clamm0363/Portfolio-Page` |
| Repository reference | `refs/heads/main` |
| Compose path | `docker-compose.yml` |

**GitHubのプライベートリポジトリの場合:**
- **Authentication** にチェックを入れる
- **Username**: GitHubのユーザー名（例: `clamm0363`）
- **Personal Access Token**: GitHubで生成したPAT（`repo`スコープが必要）

#### 2.4 環境変数の設定

**Environment variables** セクションで、以下を追加：

```
UMAMI_DB_NAME=umami
UMAMI_DB_USER=umami
UMAMI_DB_PASSWORD=<あなたの強力なパスワード>
UMAMI_HASH_SALT=<64文字のランダムな16進数文字列>
POSTGRES_DB=umami
POSTGRES_USER=umami
POSTGRES_PASSWORD=<UMAMI_DB_PASSWORDと同じ値>
```

💡 **重要**: パスワードは必ず強力なものを使用してください

#### 2.5 デプロイ

- スタック名を入力（例: `portfolio-site`）
- **Deploy the stack** ボタンをクリック

### 3. デプロイ後の確認

#### 3.1 コンテナの起動確認

Portainerの **Containers** ページで以下が起動していることを確認：
- `portfolio-nginx` - Webサーバー
- `portfolio-umami` - アクセス解析
- `portfolio-umami-db` - PostgreSQLデータベース

#### 3.2 ポートフォリオサイトへのアクセス

ブラウザで `http://<サーバーのIPまたはドメイン>` にアクセスして、ポートフォリオページが表示されることを確認します。

#### 3.3 Umamiの初期設定

1. `http://<サーバーのIPまたはドメイン>:3000` にアクセス
2. デフォルトの認証情報でログイン：
   - ユーザー名: `admin`
   - パスワード: `umami`
3. **必ずすぐにパスワードを変更してください**
4. 新しいウェブサイトを追加：
   - 名前: `Portfolio Site`
   - ドメイン: あなたのサイトのドメイン（例: `example.com`）
5. 生成されたトラッキングコード（`<script>`タグ）をコピー
6. `index.html`の`<head>`セクション内に追加

### 4. 再デプロイ（更新時）

コードを更新した後、Portainerで以下を実行：

1. **Stacks** ページで該当スタックを選択
2. **Pull and redeploy** ボタンをクリック
   - これにより、GitHubから最新のコードを取得して再デプロイされます

## トラブルシューティング

### コンテナが起動しない

1. Portainerのログを確認（Dozzleなどのログビューアーが便利）
2. 環境変数が正しく設定されているか確認
3. ボリュームの競合がないか確認（古いボリュームが残っている場合は削除）

### Umamiが502 Bad Gatewayを返す

PostgreSQLのパスワード認証が失敗している可能性があります：

1. **Volumes** ページで `portfolio-site_umami_db_data` ボリュームを削除
2. スタックを **Pull and redeploy** で再デプロイ
3. これによりデータベースが新しいパスワードで再初期化されます

### Nginxのマウントエラー

このリポジトリは `Dockerfile.nginx` を使用して静的ファイルをイメージに埋め込んでいます。
通常、ファイルマウントの問題は発生しません。

## セキュリティ上の注意

- ✅ `.env` ファイルは**絶対にGitにコミットしないでください**
- ✅ Portainerの環境変数に直接パスワードを設定してください
- ✅ Umamiのデフォルトパスワードをすぐに変更してください
- ✅ GitHub PATは必要最小限のスコープ（`repo`のみ）で生成してください

## アーキテクチャ

```
┌─────────────────┐
│   Cloudflare    │ (オプション: Tunnel経由で公開)
│     Tunnel      │
└────────┬────────┘
         │
┌────────▼────────┐
│  Nginx (Port 80)│ ポートフォリオサイト
└────────┬────────┘
         │
┌────────▼──────────┐
│ Umami (Port 3000) │ アクセス解析
└────────┬──────────┘
         │
┌────────▼─────────┐
│ PostgreSQL (5432)│ データベース
└──────────────────┘
```

## リソース

- [Portainer公式ドキュメント](https://docs.portainer.io/)
- [Umami公式ドキュメント](https://umami.is/docs)
- [Docker Compose公式ドキュメント](https://docs.docker.com/compose/)
