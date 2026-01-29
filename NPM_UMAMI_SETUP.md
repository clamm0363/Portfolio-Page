# Nginx Proxy Manager - Umami設定手順

## 🎯 目的

`analytics.clamm-translation.net` でUmamiにアクセスできるようにする

## 📝 設定手順

### 1. NPMにログイン

ブラウザで以下にアクセス：
```
http://192.168.0.110:81
```

デフォルトログイン情報（初回のみ）：
- Email: `admin@example.com`
- Password: `changeme`

### 2. Proxy Hostを追加

1. 左メニューから **「Hosts」** → **「Proxy Hosts」** をクリック

2. 右上の **「Add Proxy Host」** ボタンをクリック

### 3. Details タブで設定

| 項目 | 設定値 |
|------|--------|
| **Domain Names** | `analytics.clamm-translation.net` |
| **Scheme** | `http` |
| **Forward Hostname / IP** | `192.168.0.94` |
| **Forward Port** | `3002` |
| **Cache Assets** | オフ（動的コンテンツのため） |
| **Block Common Exploits** | オン ✓ |
| **Websockets Support** | オン ✓ |

### 4. SSL タブで設定

| 項目 | 設定値 |
|------|--------|
| **SSL Certificate** | `None` |
| **Force SSL** | オフ |
| **HTTP/2 Support** | オフ（デフォルト） |
| **HSTS Enabled** | オフ（デフォルト） |

**理由**: Cloudflareが既にSSLを提供しているため、NPM側でSSL証明書は不要

### 5. Advanced タブ（オプション - セキュリティ強化）

もし特定のIPからのみアクセスを許可したい場合：

```nginx
# 自宅のIPアドレスのみ許可（例）
allow YOUR_HOME_IP_ADDRESS;
deny all;
```

または、CORSヘッダーを追加する場合：

```nginx
# CORS設定（トラッキングスクリプト用）
add_header 'Access-Control-Allow-Origin' '*';
add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS';
add_header 'Access-Control-Allow-Headers' 'Content-Type';
```

### 6. 保存

**「Save」** ボタンをクリック

## ✅ 確認

設定完了後、数分待ってから：

```powershell
# DNS確認
nslookup analytics.clamm-translation.net

# ブラウザでアクセス
start https://analytics.clamm-translation.net
```

Umami管理画面が表示されればOK！

## 🔧 トラブルシューティング

### 502 Bad Gateway

**原因**: Umamiコンテナが起動していない

**確認**:
```powershell
ssh root@192.168.0.94 "docker compose -f /root/portfolio/docker-compose.yml ps"
```

**解決**:
```powershell
ssh root@192.168.0.94 "docker compose -f /root/portfolio/docker-compose.yml restart umami"
```

### 522 Connection timed out

**原因**: NPMがUmamiに接続できない

**確認**:
- Forward Hostname/IP: `192.168.0.94` が正しいか
- Forward Port: `3002` が正しいか
- Umamiが起動しているか

### アクセスできない

**確認**:
```powershell
# 内部からアクセステスト
curl http://192.168.0.94:3002
```

正常に応答すれば、NPMまたはCloudflare Tunnelの設定を確認

---

**次のステップ**: NPMでProxy Hostを追加してください！
