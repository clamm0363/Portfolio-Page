# Umami 外部公開設定ガイド

## 🎯 目的

HTTPSサイト（`https://clamm-translation.net`）でUmamiトラッキングを機能させるため、Umamiをサブドメイン経由で外部公開します。

## ⚠️ Mixed Content問題

現在の問題：
- ポートフォリオサイト: `https://clamm-translation.net` (HTTPS)
- Umamiスクリプト: `http://192.168.0.94:3002/script.js` (HTTP)

HTTPSサイトからHTTPリソースを読み込むことはセキュリティリスクのため、ブラウザがブロックします。

## ✅ 解決方法: Cloudflare Tunnel経由でUmamiを公開

### ステップ1: Cloudflare Tunnelに新しいPublic Hostnameを追加

1. **Cloudflare Zero Trustダッシュボード**にアクセス
   - https://one.dash.cloudflare.com/

2. **Access → Tunnels → Home-lab** をクリック

3. **Public Hostname タブ**を選択

4. **「Add a public hostname」** をクリック

5. **以下を設定**:
   ```
   Subdomain: analytics
   Domain: clamm-translation.net
   Path: （空欄）
   Type: HTTP
   URL: 192.168.0.110:80
   ```

6. **「Save hostname」** をクリック

### ステップ2: Nginx Proxy Managerに新しいProxy Hostを追加

1. **NPMにログイン**: http://192.168.0.110:81

2. **Proxy Hosts → Add Proxy Host**

3. **Detailsタブ**:
   ```
   Domain Names: analytics.clamm-translation.net
   Scheme: http
   Forward Hostname / IP: 192.168.0.94
   Forward Port: 3002
   Cache Assets: オフ（動的コンテンツのため）
   Block Common Exploits: オン
   Websockets Support: オン
   ```

4. **SSLタブ**:
   ```
   SSL Certificate: None
   Force SSL: オフ
   ```
   ※Cloudflareが既にSSLを提供

5. **Advanced タブ（オプション）**:
   ```nginx
   # IP制限を追加する場合
   allow 自宅のIPアドレス;
   deny all;
   ```

6. **「Save」** をクリック

### ステップ3: index.htmlのUmamiトラッキングコードを更新

**変更前**:
```html
<script async src="http://192.168.0.94:3002/script.js" data-website-id="161dac3e-d73c-4590-884a-3037cce71710"></script>
```

**変更後**:
```html
<script async src="https://analytics.clamm-translation.net/script.js" data-website-id="161dac3e-d73c-4590-884a-3037cce71710"></script>
```

### ステップ4: 変更を反映

```powershell
# ローカルで編集後
cd c:\Users\masar\portfolio
git add index.html
git commit -m "Update Umami tracking code to use external URL"
git push origin main

# サーバーに反映
scp index.html root@192.168.0.94:/root/portfolio/
ssh root@192.168.0.94 "docker compose -f /root/portfolio/docker-compose.yml restart nginx"
```

### ステップ5: 動作確認

1. **DNS伝播を確認**:
   ```powershell
   nslookup analytics.clamm-translation.net
   ```

2. **ブラウザでアクセス**:
   - https://analytics.clamm-translation.net
   - Umami管理画面が表示されることを確認

3. **ポートフォリオサイトでトラッキングを確認**:
   - https://clamm-translation.net にアクセス
   - ブラウザの開発者ツール（F12）→ Console
   - `script.js` が正常にロードされているか確認

4. **Umamiダッシュボードで確認**:
   - https://analytics.clamm-translation.net にログイン
   - リアルタイムでアクセスが記録されているか確認

## 🔐 セキュリティ強化（オプション）

### Cloudflare Accessで保護

Umami管理画面を認証で保護：

1. **Cloudflare Zero Trust → Access → Applications**

2. **「Add an application」** → **Self-hosted**

3. **Application Configuration**:
   ```
   Application name: Umami Analytics
   Session Duration: 24 hours
   Application domain: analytics.clamm-translation.net
   ```

4. **Policy Configuration**:
   ```
   Policy name: Allow myself
   Action: Allow
   
   Include:
   - Emails: あなたのメールアドレス
   ```

5. **「Save application」**

これで、Umami管理画面にアクセスする際、Cloudflareの認証が必要になります。

### Nginx Proxy ManagerでIP制限

特定のIPアドレスからのみアクセスを許可：

1. **NPM → Proxy Hosts → analytics.clamm-translation.net → Edit**

2. **Advanced タブ**:
   ```nginx
   # 自宅のIPアドレスのみ許可
   allow あなたの自宅のIPアドレス/32;
   deny all;
   ```

3. **「Save」**

## 🔄 データフロー（完成形）

```
ユーザー（ブラウザ）
    ↓ HTTPS
Cloudflare CDN
    ↓
Cloudflare Tunnel（暗号化）
    ↓
192.168.0.94:cloudflared
    ↓ HTTP
192.168.0.110:80（NPM）
    ↓ HTTP
192.168.0.94:3002（Umami）
    ↓
PostgreSQL
```

## 📊 完成後のURL構成

| サービス | URL | アクセス元 |
|---------|-----|----------|
| ポートフォリオ | https://clamm-translation.net | 公開 |
| Umami管理画面 | https://analytics.clamm-translation.net | 保護推奨 |
| Umamiトラッキング | https://analytics.clamm-translation.net/script.js | 公開 |

## 🐛 トラブルシューティング

### 問題1: analytics.clamm-translation.net にアクセスできない

**確認**:
```powershell
# DNS確認
nslookup analytics.clamm-translation.net

# NPM設定確認
# http://192.168.0.110:81 でProxy Hostを確認

# Umamiコンテナ確認
ssh root@192.168.0.94 "docker compose -f /root/portfolio/docker-compose.yml ps"
```

### 問題2: script.jsがロードされない（CORS エラー）

**原因**: CORS設定が不足

**解決**: NPM Advanced設定に追加
```nginx
add_header 'Access-Control-Allow-Origin' '*';
add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
```

### 問題3: トラッキングが記録されない

**確認**:
1. ブラウザのConsoleでエラーを確認
2. Umami管理画面でWebsite IDが正しいか確認
3. Umamiログを確認:
   ```powershell
   ssh root@192.168.0.94 "docker compose -f /root/portfolio/docker-compose.yml logs umami"
   ```

## 💡 代替案：トラッキングを内部のみに制限

もしUmamiを外部公開したくない場合：

### 内部アクセスのみトラッキング

```html
<!-- 内部ネットワークからのアクセスのみトラッキング -->
<script>
  if (window.location.hostname === 'localhost' || window.location.hostname.startsWith('192.168.')) {
    // 内部アクセス用のUmamiスクリプト
    const script = document.createElement('script');
    script.async = true;
    script.src = 'http://192.168.0.94:3002/script.js';
    script.setAttribute('data-website-id', '161dac3e-d73c-4590-884a-3037cce71710');
    document.head.appendChild(script);
  }
</script>
```

この方法では、外部からのアクセスはトラッキングされません。

## 🎊 まとめ

**推奨設定**:
1. ✅ UmamiをCloudflare Tunnel経由で外部公開（`analytics.clamm-translation.net`）
2. ✅ トラッキングコードをHTTPS URLに変更
3. ✅ Cloudflare Accessで管理画面を保護

この設定により：
- Mixed Content警告が解消
- 外部からのアクセスも正確にトラッキング
- セキュアな管理画面アクセス

---

**次のステップ**: Cloudflare TunnelにUmami用のPublic Hostnameを追加してください！
