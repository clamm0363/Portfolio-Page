# analytics.clamm-translation.net 接続失敗のトラブルシュート

## 想定される流れ

```
ブラウザ → DNS(CNAME) → Cloudflare → Tunnel(192.168.0.94) → NPM(192.168.0.110:80) → Umami(192.168.0.94:3002)
```

CNAME が自動追加されていて名前解決はできている場合、失敗しているのは **Tunnel → NPM → Umami** のいずれかです。

---

## 1. ブラウザのエラー内容を確認する

アクセスしたときに表示される内容を確認してください。

| 表示 | 想定原因 |
|------|----------|
| **502 Bad Gateway** | NPM は届いているが、NPM → Umami または Tunnel → NPM のどちらかが失敗 |
| **504 Gateway Timeout** | タイムアウト（NPM や Umami が応答しない） |
| **Connection refused** / 接続がリセットされた | ポートが閉いている、またはサービスが止まっている |
| **ERR_NAME_NOT_RESOLVED** | DNS の問題（CNAME が無い・間違い・伝播待ち） |
| **523 Origin is unreachable** | Cloudflare からオリジン（Tunnel 先）に届いていない |

メッセージの**全文**またはスクリーンショットがあると原因を特定しやすいです。

---

## 2. NPM に Proxy Host があるか確認する

1. **NPM にログイン**: http://192.168.0.110:81  
2. **Hosts** → **Proxy Hosts** を開く  
3. **analytics.clamm-translation.net** 用の Proxy Host が **1件** あるか確認  

### なければ追加する

- **Domain Names**: `analytics.clamm-translation.net`
- **Scheme**: `http`
- **Forward Hostname / IP**: `192.168.0.94`
- **Forward Port**: `3002`
- **SSL**: None（Cloudflare が SSL を終端するため）

詳細は `NPM_UMAMI_SETUP.md` を参照。

### ある場合は内容を確認する

- Forward 先が **192.168.0.94** と **3002** になっているか  
- ドメインが **analytics.clamm-translation.net** のみで、余計なスペースや typo がないか  

---

## 3. Tunnel から NPM に届いているか確認する（Tunnel ホストで実行）

Tunnel（cloudflared）が動いている **192.168.0.94** に SSH できる場合:

```bash
# NPM の 80 番に届くか
curl -I -H "Host: analytics.clamm-translation.net" http://192.168.0.110:80/

# Umami に直接届くか
curl -I http://192.168.0.94:3002/
```

- 192.168.0.110:80 が「Connection refused」なら、NPM の 80 番が聞いていないか、ファイアウォールで塞がれている可能性があります。
- 192.168.0.94:3002 が「Connection refused」なら、Umami コンテナが止まっているか、ポートが違う可能性があります。

---

## 4. Umami が動いているか確認する

ポートフォリオ用 Docker が動いている **192.168.0.94** で:

```bash
# Umami コンテナの状態
docker ps | findstr umami

# または
docker ps -a
```

`umami` コンテナが **Up** で、ポート **3002** が割り当てられているか確認してください。止まっていれば `docker-compose up -d` などで起動します。

---

## 5. Cloudflare の「公開されたアプリケーションルート」を再確認する

- **公開されたアプリケーションルート**: `analytics.clamm-translation.net`（または サブドメイン `analytics` + ドメイン `clamm-translation.net`）
- **パス**: `*`
- **サービス**: `HTTP`
- **URL**: `192.168.0.110:80`（NPM のアドレス）

**URL が `192.168.0.94:3002` のままになっていないか** 確認してください。NPM 経由にする場合は必ず **192.168.0.110:80** にします。

---

## 6. 直接 Umami で試す（参考）

同じネットワーク内の PC のブラウザで:

- http://192.168.0.94:3002/

ここで Umami のログイン画面が出るなら、Umami 自体は動いています。問題は Tunnel または NPM の設定です。

---

## 次のステップ

1. ブラウザに表示されている**エラー文（502 / 504 / Connection refused など）**を教えてください。  
2. NPM の Proxy Host 一覧に **analytics.clamm-translation.net** が存在するか、および Forward 先が **192.168.0.94:3002** になっているかを確認した結果を教えてください。

この2点が分かれば、原因をかなり絞り込めます。
