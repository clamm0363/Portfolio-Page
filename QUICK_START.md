# ポートフォリオサイト クイックスタートガイド

## 🎯 概要

このガイドに従って、ポートフォリオサイトを192.168.0.94のDockerホストにデプロイします。

## 📋 前提条件

- [ ] Portainerが192.168.0.94:9443で稼働中
- [ ] GitHubリポジトリにすべてのファイルがプッシュ済み
- [ ] このPCから192.168.0.94にアクセス可能

## 🚀 デプロイ手順（3ステップ）

### ステップ1: Portainer APIトークンを取得

1. ブラウザで https://192.168.0.94:9443 にアクセス
2. ログイン後、右上のユーザーアイコン → **My account**
3. **API keys** セクションで **+ Add API key**
4. Description: `Portfolio Deployment`
5. **表示されたトークンをコピー**（例: `ptr_xxxxxxxxxxxxx`）

詳細: `PORTAINER_API_SETUP.md` を参照

### ステップ2: 自動デプロイスクリプトを実行

PowerShellで以下を実行：

```powershell
cd c:\Users\masar\portfolio
.\deploy-portfolio.ps1 -ApiToken "ptr_あなたのトークン"
```

**例:**
```powershell
.\deploy-portfolio.ps1 -ApiToken "ptr_abc123def456"
```

スクリプトは自動的に：
- ✅ Portainerに接続
- ✅ 既存のスタックを削除（存在する場合）
- ✅ GitHubリポジトリからスタックを作成
- ✅ 環境変数を設定
- ✅ コンテナを起動

### ステップ3: 動作確認

数分待ってから、以下にアクセス：

- **ポートフォリオサイト**: http://192.168.0.94
- **Umami管理画面**: http://192.168.0.94:3002

## 🎨 Umami初期設定

### 1. Umamiにログイン

http://192.168.0.94:3002 にアクセス

- Username: `admin`
- Password: `umami`

### 2. パスワードを変更

⚠️ **セキュリティ重要**: すぐにパスワードを変更してください！

### 3. サイトを追加

1. **Settings** → **Websites** → **+ Add website**
2. 以下を入力：
   - Name: `Portfolio`
   - Domain: `clamm-translation.net`
3. **Save**

### 4. トラッキングコードを取得

1. 作成したWebsiteをクリック
2. **Tracking code** タブ
3. スクリプトタグをコピー

例:
```html
<script async src="http://192.168.0.94:3002/script.js" data-website-id="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"></script>
```

### 5. index.htmlにトラッキングコードを追加

`index.html` の22行目を編集：

**変更前:**
```html
<!-- <script async src="https://your-umami-instance.com/script.js" data-website-id="your-website-id"></script> -->
```

**変更後:**
```html
<script async src="http://192.168.0.94:3002/script.js" data-website-id="実際のID"></script>
```

### 6. 変更をデプロイ

```powershell
git add index.html
git commit -m "Add Umami tracking code"
git push origin main
```

Portainerでスタックを更新：

**方法A: UIから**
1. Portainerで **Stacks** → **portfolio-site**
2. **Pull and redeploy** をクリック

**方法B: スクリプトから**
```powershell
.\deploy-portfolio.ps1 -ApiToken "your-token"
```

## ✅ 完了チェックリスト

- [ ] Portainer APIトークンを取得した
- [ ] `deploy-portfolio.ps1` を実行した
- [ ] http://192.168.0.94 でポートフォリオが表示される
- [ ] http://192.168.0.94:3002 でUmami管理画面にアクセスできる
- [ ] Umamiのパスワードを変更した
- [ ] Umamiでサイトを追加した
- [ ] index.htmlにトラッキングコードを追加した
- [ ] 変更をGitHubにプッシュした
- [ ] Portainerでスタックを更新した

## 📚 詳細ドキュメント

- **Portainer API詳細**: `PORTAINER_API_SETUP.md`
- **手動デプロイ手順**: `PORTAINER_DEPLOY.md`
- **プロジェクト概要**: `README.md`

## 🔧 トラブルシューティング

### コンテナが起動しない

Portainerでログを確認：
1. **Stacks** → **portfolio-site**
2. 各コンテナの **Logs** を確認

### ポートが競合している

エラー: `bind: address already in use`

**解決方法:**
1. `docker-compose.yml` のポート番号を変更
2. 例: `"80:80"` → `"8080:80"`
3. Git commit & push
4. Portainerで **Pull and redeploy**

### Umamiが表示されない

1. Portainerで `portfolio-umami-db` のヘルスチェック確認
2. 環境変数が正しく設定されているか確認
3. コンテナのログを確認

## 🌐 次のステップ（オプション）

### Cloudflare Tunnelで外部公開

詳細は `README.md` の「Cloudflare Tunnel設定」セクションを参照

### カスタマイズ

- `assets/images/` にプロフィール画像を追加
- `assets/css/` にカスタムCSSを追加
- `index.html` を編集してコンテンツを更新

### 自動更新

Watchtowerを追加すると、イメージの自動更新が可能です（現在は未設定）

## 💡 ヒント

- **環境変数の更新**: `.env` ファイルを編集後、スクリプトを再実行
- **ログ確認**: Portainerの各コンテナページでリアルタイムログを確認可能
- **バックアップ**: Umamiのデータベースは定期的にバックアップ推奨

## 📞 サポート

問題が発生した場合：
1. このディレクトリ内の各ドキュメントを確認
2. Portainerのログを確認
3. GitHubリポジトリのIssuesで報告

---

**準備完了！デプロイを開始しましょう 🚀**
