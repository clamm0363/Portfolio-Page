# Umami 初期設定手順

## ✅ デプロイ完了

おめでとうございます！ポートフォリオサイトのデプロイが完了しました。

- **ポートフォリオサイト**: http://192.168.0.94
- **Umami管理画面**: http://192.168.0.94:3002

## 📊 Umami初期設定（5分）

### ステップ1: Umamiにログイン

1. ブラウザで **http://192.168.0.94:3002** にアクセス
2. デフォルトの管理者アカウントでログイン：
   - **Username**: `admin`
   - **Password**: `umami`

### ステップ2: パスワードを変更（重要！）

⚠️ **セキュリティ重要**: デフォルトパスワードは公開情報です。すぐに変更してください！

1. 右上のユーザーアイコンをクリック
2. **Profile** を選択
3. **Change password** セクション：
   - Current password: `umami`
   - New password: 強力な新しいパスワード
   - Confirm password: 同じパスワードを再入力
4. **Save** をクリック

### ステップ3: Websiteを追加

1. 左サイドバーから **Settings** をクリック
2. **Websites** タブを選択
3. **+ Add website** ボタンをクリック
4. 以下を入力：
   - **Name**: `Portfolio` （任意の名前）
   - **Domain**: `clamm-translation.net` （または実際のドメイン）
   - **Enable share URL**: オフのまま（任意）
5. **Save** をクリック

### ステップ4: トラッキングコードを取得

1. 作成したWebsite（Portfolio）をクリック
2. **Edit** ボタンをクリック
3. **Tracking code** タブを選択
4. 表示されるスクリプトタグ全体をコピー

例：
```html
<script async src="http://192.168.0.94:3002/script.js" data-website-id="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"></script>
```

**重要**: `data-website-id` の値は自動生成される一意のIDです。必ずあなたの実際のIDをコピーしてください。

### ステップ5: トラッキングコードをindex.htmlに追加

#### 方法A: ローカルで編集してプッシュ（推奨）

1. `c:\Users\masar\portfolio\index.html` を開く
2. 22行目を探す：
   ```html
   <!-- <script async src="https://your-umami-instance.com/script.js" data-website-id="your-website-id"></script> -->
   ```
3. コメントを解除して、実際のトラッキングコードに置き換える：
   ```html
   <script async src="http://192.168.0.94:3002/script.js" data-website-id="あなたの実際のID"></script>
   ```
4. ファイルを保存
5. Gitにコミット＆プッシュ：
   ```powershell
   cd c:\Users\masar\portfolio
   git add index.html
   git commit -m "Add Umami tracking code"
   git push origin main
   ```
6. サーバー側で最新版を取得：
   ```powershell
   ssh root@192.168.0.94 "cd /root/portfolio && git pull && docker compose restart nginx"
   ```

#### 方法B: サーバー側で直接編集

```powershell
ssh root@192.168.0.94
cd /root/portfolio
nano index.html
# 22行目を編集
# Ctrl+O で保存、Ctrl+X で終了
docker compose restart nginx
```

### ステップ6: 動作確認

1. ブラウザで **http://192.168.0.94** にアクセス
2. ページを数回リロード
3. Umami管理画面（**http://192.168.0.94:3002**）に戻る
4. **Dashboard** を確認
5. リアルタイムでアクセスが記録されているか確認

## 🎉 完了！

すべての設定が完了しました。これで：

✅ ポートフォリオサイトが http://192.168.0.94 で公開中
✅ Umamiでアクセス解析が稼働中
✅ すべてのコンテナがDockerで管理されている

## 🌐 次のステップ（オプション）

### Cloudflare Tunnelで外部公開

現在は192.168.0.94（内部ネットワーク）でのみアクセス可能です。
インターネットから `clamm-translation.net` でアクセスできるようにするには：

1. **README.md** の「Cloudflare Tunnel設定」セクションを参照
2. Cloudflare Tunnelを設定
3. DNS設定（CNAME）を追加

### カスタマイズ

- **プロフィール画像**: `assets/images/` に画像を追加し、`index.html` で参照
- **カスタムCSS**: `assets/css/` に `.css` ファイルを追加
- **コンテンツ更新**: `index.html` を編集して作品を追加・更新

### バックアップ

Umamiのデータベースを定期的にバックアップ：

```bash
ssh root@192.168.0.94
cd /root/portfolio
docker compose exec umami-db pg_dump -U umami umami > umami_backup_$(date +%Y%m%d).sql
```

## 🔧 トラブルシューティング

### ポートフォリオサイトが表示されない

```bash
ssh root@192.168.0.94
cd /root/portfolio
docker compose logs nginx
```

### Umamiが起動しない

```bash
ssh root@192.168.0.94
cd /root/portfolio
docker compose logs umami
docker compose logs umami-db
```

### トラッキングが機能しない

1. ブラウザの開発者ツール（F12）→ Console を確認
2. `script.js` が正常にロードされているか確認
3. Umamiの管理画面でWebsite IDが正しいか確認

### コンテナを再起動

```bash
ssh root@192.168.0.94
cd /root/portfolio
docker compose restart
```

## 📚 参考ドキュメント

- **README.md**: プロジェクト全体の概要
- **QUICK_START.md**: クイックスタートガイド
- **PORTAINER_DEPLOY.md**: Portainerを使ったデプロイ手順
- **PORTAINER_API_SETUP.md**: Portainer API設定

## 💡 ヒント

- **更新の反映**: `index.html` を更新したら `docker compose restart nginx`
- **ログ監視**: `docker compose logs -f` でリアルタイムログを表示
- **環境変数変更**: `.env` を更新したら `docker compose up -d` で再デプロイ

---

**🎊 デプロイ完了おめでとうございます！**
