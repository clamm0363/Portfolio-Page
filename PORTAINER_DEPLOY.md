# Portainerを使用したポートフォリオサイトのデプロイ手順

## 前提条件

- **Portainer URL**: https://192.168.0.94:9443
- **GitHubリポジトリ**: https://github.com/clamm0363/Portfolio-Page
- **Dockerホスト**: 192.168.0.94

## デプロイ手順

### 1. Portainerにログイン

1. ブラウザで `https://192.168.0.94:9443` にアクセス
2. Portainerの管理者アカウントでログイン

### 2. 新しいStackを作成

1. 左サイドバーから **Stacks** をクリック
2. **Add stack** ボタンをクリック
3. Stack名を入力: `portfolio-site`

### 3. デプロイ方法を選択

**Repository** タブを選択し、以下を入力：

- **Repository URL**: `https://github.com/clamm0363/Portfolio-Page`
- **Repository reference**: `refs/heads/main`
- **Compose path**: `docker-compose.yml`
- **Authentication**: 不要（パブリックリポジトリの場合）

プライベートリポジトリの場合：
- **Authentication**: オン
- **Username**: GitHubユーザー名
- **Personal Access Token**: GitHubのPATを入力

### 4. 環境変数を設定

**Environment variables** セクションで、以下の環境変数を追加：

```
UMAMI_DB_NAME=umami
UMAMI_DB_USER=umami
UMAMI_DB_PASSWORD=FloYM2gp3ZGtKN9ADnPJxvsiEWuRhk45
UMAMI_HASH_SALT=54becf58b9d2c60dd2b53dfd36e683b0e72fb5d34c91d82bad4150f72cdd5ff4
```

**重要**: 本番環境では、これらの値を必ず変更してください！

### 5. ポート設定の確認

docker-compose.ymlで定義されているポート：

- **80**: Nginxポートフォリオサイト
- **443**: Nginx HTTPS（未使用）
- **3002**: Umami管理画面

**注意**: ポート80と3002が他のコンテナで使用されていないことを確認してください。
もし競合する場合は、docker-compose.ymlの `ports` セクションを編集してください。

### 6. Stackをデプロイ

1. すべての設定を確認
2. 下部の **Deploy the stack** ボタンをクリック
3. デプロイが完了するまで待機（数分かかる場合があります）

### 7. デプロイの確認

#### 7.1 コンテナの状態確認

1. Portainerの **Stacks** → **portfolio-site** をクリック
2. 以下の3つのコンテナが "running" 状態であることを確認：
   - `portfolio-nginx`
   - `portfolio-umami`
   - `portfolio-umami-db`

#### 7.2 サイトへのアクセス

- **ポートフォリオサイト**: http://192.168.0.94
- **Umami管理画面**: http://192.168.0.94:3002

### 8. Umami初期設定

1. http://192.168.0.94:3002 にアクセス
2. 初回起動時、デフォルトの管理者アカウントでログイン：
   - Username: `admin`
   - Password: `umami`
3. **すぐにパスワードを変更してください！**
4. 新しいWebサイトを追加：
   - Name: `Portfolio`
   - Domain: `clamm-translation.net`
5. トラッキングコードをコピー
6. `index.html` の22行目のコメントを解除し、トラッキングコードを貼り付け
7. 変更をGitHubにプッシュ
8. Portainerで **Pull and redeploy** を実行

## トラブルシューティング

### ポートが競合している場合

Portainerのログを確認：
```
Error: bind: address already in use
```

**解決方法**:
1. Gitでdocker-compose.ymlのportsセクションを編集
2. 例: `"80:80"` → `"8080:80"`
3. コミット & プッシュ
4. Portainerで **Pull and redeploy**

### Umamiが起動しない場合

1. Portainerでコンテナのログを確認
2. データベースのヘルスチェックが成功しているか確認
3. 環境変数が正しく設定されているか確認

### Stack更新方法

GitHubにコードを更新した後：

1. Portainerの **Stacks** → **portfolio-site** を開く
2. **Pull and redeploy** ボタンをクリック
3. 最新のコードが自動的にデプロイされます

## 公開設定（オプション）

Cloudflare Tunnelを使用して外部公開する場合は、README.mdの「Cloudflare Tunnel設定」セクションを参照してください。

## セキュリティ注意事項

1. **環境変数**: 本番環境では必ずランダムな強力なパスワードを使用
2. **Umamiパスワード**: デフォルトパスワードを必ず変更
3. **Portainerアクセス**: 信頼できるネットワークからのみアクセス
4. **.env情報**: この文書に記載されているパスワードは例です。本番環境では変更必須！

## 連絡先

問題が発生した場合は、GitHubリポジトリのIssuesで報告してください。
