# Cloudflare Tunnel 設定完了ガイド

## ✅ 現在の状態

- **cloudflared**: インストール済み（192.168.0.94）
- **サービス**: 起動中（systemd）
- **トンネル接続**: 4つの接続が確立済み

## 🌐 次のステップ: ルーティング設定

### Cloudflareダッシュボードでの操作

1. **「次へ」をクリック**
   - 画面下部の「次へ」または「Continue」ボタンをクリック

2. **Public Hostnameを設定**

   **Subdomain（サブドメイン）**:
   - 空欄のまま（ルートドメインを使用）
   - または `www` を入力（www.clamm-translation.net を使用する場合）

   **Domain（ドメイン）**:
   - `clamm-translation.net` を選択（ドロップダウンから）

   **Path（パス）**:
   - 空欄のまま

   **Type（タイプ）**:
   - `HTTP` を選択

   **URL**:
   - `localhost:80` を入力
   - または `192.168.0.94:80` を入力

3. **「Save tunnel」をクリック**

### 設定例

#### パターン1: ルートドメイン（推奨）
```
Subdomain: （空欄）
Domain: clamm-translation.net
Path: （空欄）
Type: HTTP
URL: localhost:80
```
結果: `https://clamm-translation.net` → `http://192.168.0.94:80`

#### パターン2: wwwサブドメイン
```
Subdomain: www
Domain: clamm-translation.net
Path: （空欄）
Type: HTTP
URL: localhost:80
```
結果: `https://www.clamm-translation.net` → `http://192.168.0.94:80`

## 📊 DNS設定（自動）

Cloudflare Tunnelを保存すると、DNSレコードが自動的に作成されます：

- **Type**: CNAME
- **Name**: @ （またはwww）
- **Target**: `xxxx.cfargotunnel.com`
- **Proxy status**: Proxied（オレンジの雲）

手動でDNS設定を確認する場合：
1. Cloudflareダッシュボード → DNS → Records
2. CNAMEレコードが作成されていることを確認

## 🔐 SSL/TLS設定

1. Cloudflareダッシュボード → SSL/TLS
2. **Encryption mode**: `Flexible` または `Full`
   - `Flexible`: Cloudflare ↔ ユーザー間のみSSL（推奨・簡単）
   - `Full`: Cloudflare ↔ オリジンサーバーもSSL（要証明書）

3. **Always Use HTTPS**: オン（推奨）
   - HTTP → HTTPS自動リダイレクト

## ✅ 動作確認

### 1. トンネルの状態確認

```bash
ssh root@192.168.0.94 "systemctl status cloudflared"
```

### 2. アクセステスト

設定完了後、数分待ってから：

```bash
# HTTPSでアクセス
curl -I https://clamm-translation.net

# ブラウザでアクセス
# https://clamm-translation.net
```

### 3. Umamiの動作確認

- Umami管理画面: http://192.168.0.94:3002
- 外部からのアクセスがダッシュボードに表示されるか確認

## 🔧 トラブルシューティング

### トンネルが接続されない

```bash
# ログ確認
ssh root@192.168.0.94 "journalctl -u cloudflared -f"

# サービス再起動
ssh root@192.168.0.94 "systemctl restart cloudflared"
```

### サイトにアクセスできない

1. **DNS伝播を確認**
   ```bash
   nslookup clamm-translation.net
   ```
   CNAMEレコードが `cfargotunnel.com` を指しているか確認

2. **Cloudflare DNS設定を確認**
   - Cloudflareダッシュボード → DNS → Records
   - CNAMEレコードが存在し、Proxy（オレンジの雲）が有効か確認

3. **nginx設定を確認**
   ```bash
   ssh root@192.168.0.94 "docker compose -f /root/portfolio/docker-compose.yml logs nginx"
   ```

### 522エラー（Connection timed out）

Cloudflare → オリジンサーバーの接続に問題があります：

```bash
# nginxが起動しているか確認
ssh root@192.168.0.94 "docker compose -f /root/portfolio/docker-compose.yml ps"

# nginxを再起動
ssh root@192.168.0.94 "docker compose -f /root/portfolio/docker-compose.yml restart nginx"
```

### 525エラー（SSL handshake failed）

SSL/TLS設定を `Flexible` に変更してください。

## 📈 追加設定（オプション）

### Umamiも外部公開する場合

追加のPublic Hostnameを設定：

```
Subdomain: analytics
Domain: clamm-translation.net
Type: HTTP
URL: localhost:3002
```

結果: `https://analytics.clamm-translation.net` → Umami管理画面

⚠️ **セキュリティ注意**: Umamiを公開する場合、強力なパスワードを設定してください。

### Cloudflare Access（オプション）

Umami管理画面をCloudflare Accessで保護：
1. Zero Trust → Access → Applications
2. 新しいアプリケーションを作成
3. `analytics.clamm-translation.net` を保護

## 🎊 完了！

設定が完了すると：

- ✅ `https://clamm-translation.net` でポートフォリオサイトにアクセス可能
- ✅ SSL/TLS（HTTPS）が自動的に有効
- ✅ Cloudflare CDNによる高速化とDDoS保護
- ✅ 内部IPアドレス（192.168.0.94）が隠蔽される

## 📚 参考リンク

- [Cloudflare Tunnel ドキュメント](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [cloudflared GitHub](https://github.com/cloudflare/cloudflared)
- [Cloudflare Zero Trust](https://www.cloudflare.com/products/zero-trust/)

## 💡 便利なコマンド

```bash
# cloudflaredサービス管理
ssh root@192.168.0.94 "systemctl status cloudflared"   # 状態確認
ssh root@192.168.0.94 "systemctl restart cloudflared"  # 再起動
ssh root@192.168.0.94 "systemctl stop cloudflared"     # 停止
ssh root@192.168.0.94 "systemctl start cloudflared"    # 開始

# ログ確認
ssh root@192.168.0.94 "journalctl -u cloudflared -n 50"  # 最新50行
ssh root@192.168.0.94 "journalctl -u cloudflared -f"      # リアルタイム

# アンインストール（必要な場合）
ssh root@192.168.0.94 "cloudflared service uninstall"
```

---

**次のステップ**: Cloudflareダッシュボードで「次へ」をクリックして、ルーティング設定を完了してください！
