# Portainer API トークンの作成手順

## APIトークンの作成

### 1. Portainerにログイン

1. ブラウザで `https://192.168.0.94:9443` にアクセス
2. 管理者アカウントでログイン

### 2. APIトークンを作成

1. 右上のユーザーアイコンをクリック
2. **My account** を選択
3. 下にスクロールして **API keys** セクションを探す
4. **+ Add API key** ボタンをクリック
5. 以下を入力：
   - **Description**: `Portfolio Deployment` （任意の名前）
6. **Add API key** ボタンをクリック
7. **表示されたAPIキーを必ずコピーして保存してください**（二度と表示されません！）

### 3. APIキーの保存

生成されたAPIキーは以下の形式です：
```
ptr_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

このキーを安全な場所に保存してください。

## Cursor / PowerShellからのAPIデプロイ

APIトークンを取得したら、以下のコマンドでスタックを自動デプロイできます。

### 手順

#### 1. 環境変数を設定

```powershell
$PORTAINER_URL = "https://192.168.0.94:9443"
$API_TOKEN = "ptr_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"  # 実際のトークンに置き換え
```

#### 2. エンドポイントIDを取得

```powershell
$headers = @{
    "X-API-Key" = $API_TOKEN
}

$endpoints = Invoke-RestMethod -Uri "$PORTAINER_URL/api/endpoints" -Headers $headers -SkipCertificateCheck
$endpointId = $endpoints[0].Id
Write-Host "Endpoint ID: $endpointId"
```

#### 3. Stackを作成

```powershell
$stackName = "portfolio-site"
$repoUrl = "https://github.com/clamm0363/Portfolio-Page"
$branch = "main"
$composePath = "docker-compose.yml"

$body = @{
    name = $stackName
    repositoryURL = $repoUrl
    repositoryReferenceName = "refs/heads/$branch"
    composeFile = $composePath
    env = @(
        @{ name = "UMAMI_DB_NAME"; value = "umami" }
        @{ name = "UMAMI_DB_USER"; value = "umami" }
        @{ name = "UMAMI_DB_PASSWORD"; value = "FloYM2gp3ZGtKN9ADnPJxvsiEWuRhk45" }
        @{ name = "UMAMI_HASH_SALT"; value = "54becf58b9d2c60dd2b53dfd36e683b0e72fb5d34c91d82bad4150f72cdd5ff4" }
    )
} | ConvertTo-Json -Depth 10

$response = Invoke-RestMethod `
    -Uri "$PORTAINER_URL/api/stacks?type=2&method=repository&endpointId=$endpointId" `
    -Method Post `
    -Headers $headers `
    -ContentType "application/json" `
    -Body $body `
    -SkipCertificateCheck

Write-Host "Stack created successfully!"
Write-Host "Stack ID: $($response.Id)"
```

#### 4. デプロイ確認

```powershell
# Stackの状態を確認
$stack = Invoke-RestMethod -Uri "$PORTAINER_URL/api/stacks/$($response.Id)" -Headers $headers -SkipCertificateCheck
$stack | ConvertTo-Json -Depth 5
```

## 完全な自動デプロイスクリプト

上記の手順をまとめた完全なスクリプト：

```powershell
# 設定
$PORTAINER_URL = "https://192.168.0.94:9443"
$API_TOKEN = "ptr_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"  # 実際のトークンに置き換え

# ヘッダー設定
$headers = @{
    "X-API-Key" = $API_TOKEN
}

try {
    # 1. エンドポイントIDを取得
    Write-Host "Fetching endpoint ID..."
    $endpoints = Invoke-RestMethod -Uri "$PORTAINER_URL/api/endpoints" -Headers $headers -SkipCertificateCheck
    $endpointId = $endpoints[0].Id
    Write-Host "Endpoint ID: $endpointId"

    # 2. 既存のスタックを確認
    Write-Host "Checking for existing stacks..."
    $stacks = Invoke-RestMethod -Uri "$PORTAINER_URL/api/stacks" -Headers $headers -SkipCertificateCheck
    $existingStack = $stacks | Where-Object { $_.Name -eq "portfolio-site" }
    
    if ($existingStack) {
        Write-Host "Stack 'portfolio-site' already exists. Deleting..."
        Invoke-RestMethod -Uri "$PORTAINER_URL/api/stacks/$($existingStack.Id)" -Method Delete -Headers $headers -SkipCertificateCheck
        Start-Sleep -Seconds 5
    }

    # 3. 新しいStackを作成
    Write-Host "Creating new stack..."
    $body = @{
        name = "portfolio-site"
        repositoryURL = "https://github.com/clamm0363/Portfolio-Page"
        repositoryReferenceName = "refs/heads/main"
        composeFile = "docker-compose.yml"
        env = @(
            @{ name = "UMAMI_DB_NAME"; value = "umami" }
            @{ name = "UMAMI_DB_USER"; value = "umami" }
            @{ name = "UMAMI_DB_PASSWORD"; value = "FloYM2gp3ZGtKN9ADnPJxvsiEWuRhk45" }
            @{ name = "UMAMI_HASH_SALT"; value = "54becf58b9d2c60dd2b53dfd36e683b0e72fb5d34c91d82bad4150f72cdd5ff4" }
        )
    } | ConvertTo-Json -Depth 10

    $response = Invoke-RestMethod `
        -Uri "$PORTAINER_URL/api/stacks?type=2&method=repository&endpointId=$endpointId" `
        -Method Post `
        -Headers $headers `
        -ContentType "application/json" `
        -Body $body `
        -SkipCertificateCheck

    Write-Host "✅ Stack created successfully!"
    Write-Host "Stack ID: $($response.Id)"
    Write-Host ""
    Write-Host "Portfolio site should be available at:"
    Write-Host "  - Portfolio: http://192.168.0.94"
    Write-Host "  - Umami: http://192.168.0.94:3002"
    
} catch {
    Write-Host "❌ Error: $($_.Exception.Message)"
    Write-Host $_.Exception
}
```

## 使用方法

1. 上記のスクリプトを `deploy-portfolio.ps1` として保存
2. `$API_TOKEN` を実際のトークンに置き換え
3. PowerShellで実行:
   ```powershell
   .\deploy-portfolio.ps1
   ```

## トラブルシューティング

### SSL証明書エラー

PowerShell 7以降を使用していない場合、`-SkipCertificateCheck` が使えません。
以下を追加してください：

```powershell
# PowerShell 5.x の場合
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
```

### APIエラー

- **401 Unauthorized**: APIトークンが無効または期限切れ
- **409 Conflict**: 同名のスタックが既に存在
- **500 Internal Server Error**: Portainerのログを確認

## 次のステップ

デプロイが完了したら、PORTAINER_DEPLOY.mdの「7. デプロイの確認」と「8. Umami初期設定」を参照してください。
