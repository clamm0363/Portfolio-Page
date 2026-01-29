# デプロイ手順（コミット・プッシュ → Portainer）

Cursor のターミナルでは `.git` への書き込みができない場合があるため、**手元の PowerShell または Git Bash** で以下を実行してください。

---

## 0. 初回セットアップ（GitHub Personal Access Token）

**プライベートリポジトリをデプロイする場合、GitHub Personal Access Token が必要です。**

### トークンの作成

1. GitHub → 右上のプロフィール → **Settings**
2. 左メニュー最下部 → **Developer settings**
3. **Personal access tokens** → **Tokens (classic)**
4. **Generate new token (classic)** をクリック
5. Note: `Portainer Deployment`
6. Expiration: お好みで（推奨：90 days または No expiration）
7. Scopeで **`repo`** にチェック（Full control of private repositories）
8. **Generate token** をクリック
9. トークンをコピー（`ghp_` で始まる文字列）

### .env ファイルへの追加

リポジトリのルート（`c:\Users\masar\portfolio`）で `.env` ファイルを編集：

```env
GITHUB_TOKEN=ghp_あなたのトークンをここに貼り付け
```

⚠️ **重要**: `.env` ファイルは `.gitignore` に含まれているため、コミットされません。

---

## 1. コミット・プッシュ

リポジトリのルート（`c:\Users\masar\portfolio`）で:

```powershell
cd c:\Users\masar\portfolio

git add index.html README.md CLOUDFLARE_TUNNEL_SETUP.md ANALYTICS_TROUBLESHOOTING.md CLOUDFLARE_ANALYTICS_ROUTE.md NPM_UMAMI_SETUP.md
git commit -m "Umami HTTPS化・analyticsサブドメイン対応"
git push
```

GitHub の認証（パスワードまたはトークン）を求められたら入力してください。

---

## 2. Portainer で再デプロイ

プッシュが成功したら、同じフォルダで:

**補足**: Portainer 2.27 以降ではスタック作成 API が変更されています。`deploy-portfolio.ps1` は新エンドポイント（`/api/stacks/create/standalone/repository`）と Bearer 認証に対応済みです。405 エラーが出ていた場合はこの修正で解消する想定です。

```powershell
$token = (Get-Content .env | Where-Object { $_ -match "^PORTAINER_API_TOKEN=" }) -replace "PORTAINER_API_TOKEN=",""
$token = $token.Trim()
.\deploy-portfolio.ps1 -ApiToken $token
```

- `.env` に `PORTAINER_API_TOKEN` と `GITHUB_TOKEN` が設定されている必要があります。
- スクリプトは既存のスタック「portfolio-site」を削除し、Git の最新版から再作成します。
- 完了まで 1〜2 分かかることがあります。

---

## 3. 動作確認

- **ポートフォリオ**: https://clamm-translation.net  
- **Umami 管理**: https://analytics.clamm-translation.net  
- サイト表示後、Umami ダッシュボードでアクセスが記録されているか確認してください。
