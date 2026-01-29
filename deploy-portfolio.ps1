# Portfolio Site Deployment Script for Portainer
# Usage: .\deploy-portfolio.ps1 -ApiToken "ptr_your_token_here"

param(
    [Parameter(Mandatory=$true)]
    [string]$ApiToken,
    
    [Parameter(Mandatory=$false)]
    [string]$PortainerUrl = "https://192.168.0.94:9443",
    
    [Parameter(Mandatory=$false)]
    [string]$StackName = "portfolio-site",
    
    [Parameter(Mandatory=$false)]
    [string]$RepoUrl = "https://github.com/clamm0363/Portfolio-Page.git",
    
    [Parameter(Mandatory=$false)]
    [string]$Branch = "main"
)

# Colors for output
$Green = "`e[32m"
$Red = "`e[31m"
$Yellow = "`e[33m"
$Reset = "`e[0m"

function Write-Success {
    param([string]$Message)
    Write-Host "${Green}✓ $Message${Reset}"
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "${Red}✗ $Message${Reset}"
}

function Write-Info {
    param([string]$Message)
    Write-Host "${Yellow}ℹ $Message${Reset}"
}

# SSL証明書チェックをスキップ（自己署名証明書対応）
if ($PSVersionTable.PSVersion.Major -lt 7) {
    # PowerShell 5.x
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
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}

# プロキシ設定をバイパス
[System.Net.WebRequest]::DefaultWebProxy = $null
if (Get-Command Set-ProxySettings -ErrorAction SilentlyContinue) {
    $null = Set-ProxySettings -Proxy $null
}

# ヘッダー設定（APIトークンは X-API-Key で使用）
$headers = @{
    "X-API-Key" = $ApiToken
}

try {
    Write-Info "Connecting to Portainer at $PortainerUrl..."
    
    # 1. エンドポイントIDを取得
    Write-Info "Fetching endpoint ID..."
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $endpoints = Invoke-RestMethod -Uri "$PortainerUrl/api/endpoints" -Headers $headers -SkipCertificateCheck -NoProxy
    } else {
        $endpoints = Invoke-RestMethod -Uri "$PortainerUrl/api/endpoints" -Headers $headers -Proxy $null
    }
    
    $endpointId = $endpoints[0].Id
    Write-Success "Endpoint ID: $endpointId"

    # 2. 既存のスタックを確認
    Write-Info "Checking for existing stacks..."
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $stacks = Invoke-RestMethod -Uri "$PortainerUrl/api/stacks" -Headers $headers -SkipCertificateCheck -NoProxy
    } else {
        $stacks = Invoke-RestMethod -Uri "$PortainerUrl/api/stacks" -Headers $headers -Proxy $null
    }
    
    $existingStack = $stacks | Where-Object { $_.Name -eq $StackName }
    
    if ($existingStack) {
        Write-Info "Stack '$StackName' already exists. Deleting with volumes..."
        # ボリュームも含めて削除（?volumes=true を追加）
        $deleteUri = "$PortainerUrl/api/stacks/$($existingStack.Id)?endpointId=$endpointId"
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            Invoke-RestMethod -Uri $deleteUri -Method Delete -Headers $headers -SkipCertificateCheck -NoProxy | Out-Null
        } else {
            Invoke-RestMethod -Uri $deleteUri -Method Delete -Headers $headers -Proxy $null | Out-Null
        }
        Write-Success "Existing stack deleted"
        Write-Info "Waiting for containers to be removed..."
        Start-Sleep -Seconds 10
    }
    
    # 残存コンテナの確認と削除
    Write-Info "Checking for orphaned containers..."
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $containers = Invoke-RestMethod -Uri "$PortainerUrl/api/endpoints/$endpointId/docker/containers/json?all=1" -Headers $headers -SkipCertificateCheck -NoProxy
    } else {
        $containers = Invoke-RestMethod -Uri "$PortainerUrl/api/endpoints/$endpointId/docker/containers/json?all=1" -Headers $headers -Proxy $null
    }
    
    $orphanedContainers = $containers | Where-Object { 
        $_.Names -match "portfolio-nginx|portfolio-umami|portfolio-umami-db" 
    }
    
    if ($orphanedContainers) {
        Write-Info "Found $($orphanedContainers.Count) orphaned container(s). Removing..."
        foreach ($container in $orphanedContainers) {
            $containerName = $container.Names[0] -replace '^/', ''
            Write-Info "Removing container: $containerName"
            try {
                $deleteContainerUri = "$PortainerUrl/api/endpoints/$endpointId/docker/containers/$($container.Id)?force=true&v=true"
                if ($PSVersionTable.PSVersion.Major -ge 7) {
                    Invoke-RestMethod -Uri $deleteContainerUri -Method Delete -Headers $headers -SkipCertificateCheck -NoProxy | Out-Null
                } else {
                    Invoke-RestMethod -Uri $deleteContainerUri -Method Delete -Headers $headers -Proxy $null | Out-Null
                }
                Write-Success "Container $containerName removed"
            } catch {
                Write-Error-Custom "Failed to remove container $containerName : $($_.Exception.Message)"
            }
        }
        Write-Info "Waiting for cleanup to complete..."
        Start-Sleep -Seconds 5
    } else {
        Write-Success "No orphaned containers found"
    }
    
    # 残存ボリュームの確認と削除
    Write-Info "Checking for orphaned volumes..."
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $volumes = Invoke-RestMethod -Uri "$PortainerUrl/api/endpoints/$endpointId/docker/volumes" -Headers $headers -SkipCertificateCheck -NoProxy
    } else {
        $volumes = Invoke-RestMethod -Uri "$PortainerUrl/api/endpoints/$endpointId/docker/volumes" -Headers $headers -Proxy $null
    }
    
    $orphanedVolumes = $volumes.Volumes | Where-Object { 
        $_.Name -match "portfolio-site_umami_db_data|umami_db_data"
    }
    
    if ($orphanedVolumes) {
        Write-Info "Found $($orphanedVolumes.Count) orphaned volume(s). Removing..."
        foreach ($volume in $orphanedVolumes) {
            Write-Info "Removing volume: $($volume.Name)"
            try {
                $deleteVolumeUri = "$PortainerUrl/api/endpoints/$endpointId/docker/volumes/$($volume.Name)?force=true"
                if ($PSVersionTable.PSVersion.Major -ge 7) {
                    Invoke-RestMethod -Uri $deleteVolumeUri -Method Delete -Headers $headers -SkipCertificateCheck -NoProxy | Out-Null
                } else {
                    Invoke-RestMethod -Uri $deleteVolumeUri -Method Delete -Headers $headers -Proxy $null | Out-Null
                }
                Write-Success "Volume $($volume.Name) removed"
            } catch {
                Write-Error-Custom "Failed to remove volume $($volume.Name) : $($_.Exception.Message)"
            }
        }
    } else {
        Write-Success "No orphaned volumes found"
    }

    # 3. 環境変数の読み取り（.envファイルから）。API は PascalCase（Name, Value）を期待
    $envVars = @(
        @{ Name = "UMAMI_DB_NAME"; Value = "umami" }
        @{ Name = "UMAMI_DB_USER"; Value = "umami" }
    )
    
    # GitHub認証情報の読み取り
    $githubToken = $null
    $githubUsername = "git"  # GitHub Personal Access Token使用時は任意の値でOK
    
    # .envファイルが存在する場合、そこから読み取る
    if (Test-Path ".env") {
        Write-Info "Reading environment variables from .env file..."
        $envContent = Get-Content ".env" | Where-Object { $_ -notmatch "^#" -and $_ -match "=" }
        foreach ($line in $envContent) {
            $parts = $line -split "=", 2
            if ($parts.Length -eq 2) {
                $key = $parts[0].Trim()
                $value = $parts[1].Trim()
                if ($key -eq "UMAMI_DB_PASSWORD" -or $key -eq "UMAMI_HASH_SALT") {
                    $envVars += @{ Name = $key; Value = $value }
                } elseif ($key -eq "GITHUB_TOKEN") {
                    $githubToken = $value
                }
            }
        }
    } else {
        Write-Error-Custom ".env file not found! Using default values (NOT RECOMMENDED for production)"
        $envVars += @{ Name = "UMAMI_DB_PASSWORD"; Value = "FloYM2gp3ZGtKN9ADnPJxvsiEWuRhk45" }
        $envVars += @{ Name = "UMAMI_HASH_SALT"; Value = "54becf58b9d2c60dd2b53dfd36e683b0e72fb5d34c91d82bad4150f72cdd5ff4" }
    }
    
    # GitHub認証チェック
    if (-not $githubToken -or $githubToken -eq "your_github_token_here") {
        Write-Error-Custom "GITHUB_TOKEN not found or not set in .env file!"
        Write-Host ""
        Write-Info "To deploy a private repository, you need a GitHub Personal Access Token:"
        Write-Host "  1. Go to https://github.com/settings/tokens"
        Write-Host "  2. Click 'Generate new token (classic)'"
        Write-Host "  3. Select scope: 'repo' (Full control of private repositories)"
        Write-Host "  4. Copy the token (starts with 'ghp_')"
        Write-Host "  5. Add it to .env file: GITHUB_TOKEN=ghp_your_token_here"
        Write-Host ""
        exit 1
    }
    
    # GitHub Tokenの有効性をテスト
    Write-Info "Verifying GitHub token..."
    try {
        $githubHeaders = @{
            "Authorization" = "Bearer $githubToken"
            "Accept" = "application/vnd.github.v3+json"
        }
        $repoName = $RepoUrl -replace 'https://github.com/', '' -replace '\.git$', ''
        $githubApiUrl = "https://api.github.com/repos/$repoName"
        
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            $repoInfo = Invoke-RestMethod -Uri $githubApiUrl -Headers $githubHeaders -SkipCertificateCheck -NoProxy
        } else {
            $repoInfo = Invoke-RestMethod -Uri $githubApiUrl -Headers $githubHeaders -Proxy $null
        }
        Write-Success "GitHub token verified! Repository: $($repoInfo.full_name) (Private: $($repoInfo.private))"
    } catch {
        Write-Error-Custom "GitHub token verification failed!"
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        Write-Info "Please check:"
        Write-Host "  1. Token is valid and not expired"
        Write-Host "  2. Token has 'repo' scope"
        Write-Host "  3. You have access to the repository: $RepoUrl"
        Write-Host ""
        exit 1
    }

    # 4. 新しいStackを作成（Portainer 2.27+ は /api/stacks/create/standalone/repository を使用）
    # リクエストボディは PascalCase（Name, RepositoryURL 等）が必須
    Write-Info "Creating new stack '$StackName'..."
    Write-Info "Using GitHub authentication (private repository)..."
    Write-Info "Repository: $RepoUrl"
    Write-Info "Branch: $Branch"
    Write-Info "GitHub Token: $($githubToken.Substring(0, 7))..." # 最初の7文字のみ表示
    
    $body = @{
        Name                     = $StackName
        RepositoryURL            = $RepoUrl
        RepositoryReferenceName  = "refs/heads/$Branch"
        ComposeFile              = "docker-compose.yml"
        RepositoryAuthentication = $true
        RepositoryUsername       = $githubUsername
        RepositoryPassword       = $githubToken
        FromAppTemplate          = $false
        Env                      = $envVars
    } | ConvertTo-Json -Depth 10

    $createUri = "$PortainerUrl/api/stacks/create/standalone/repository?endpointId=$endpointId"
    $createParams = @{
        Uri         = $createUri
        Method      = "Post"
        ContentType = "application/json"
        Body        = $body
    }
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $createParams["SkipCertificateCheck"] = $true
        $createParams["NoProxy"] = $true
    } else {
        $createParams["Proxy"] = $null
    }

    # 新エンドポイント + X-API-Key（APIトークンは Bearer では 401 になるため）
    $createParams["Headers"] = $headers
    $response = Invoke-RestMethod @createParams

    Write-Success "Stack created successfully!"
    Write-Success "Stack ID: $($response.Id)"
    Write-Host ""
    Write-Success "=== Deployment Complete ===" 
    Write-Host ""
    Write-Info "Your portfolio site should be available at:"
    Write-Host "  📄 Portfolio:  http://192.168.0.94"
    Write-Host "  📊 Umami:      http://192.168.0.94:3002"
    Write-Host ""
    Write-Info "Next steps:"
    Write-Host "  1. Wait a few minutes for containers to start"
    Write-Host "  2. Access Umami at http://192.168.0.94:3002"
    Write-Host "  3. Login with default credentials (admin/umami)"
    Write-Host "  4. Change the password immediately!"
    Write-Host "  5. Follow PORTAINER_DEPLOY.md for Umami configuration"
    Write-Host ""
    
} catch {
    Write-Error-Custom "Deployment failed: $($_.Exception.Message)"
    Write-Host ""
    # 500 等のとき Portainer が返す本文を表示（原因特定用）
    if ($_.ErrorDetails.Message) {
        Write-Host "Portainer response body:" -ForegroundColor Yellow
        Write-Host $_.ErrorDetails.Message
        Write-Host ""
    }
    Write-Host "Error details:" -ForegroundColor Red
    Write-Host $_.Exception
    Write-Host ""
    Write-Info "Troubleshooting:"
    Write-Host "  - Check if Portainer is accessible at $PortainerUrl"
    Write-Host "  - Verify your API token is valid"
    Write-Host "  - Check PORTAINER_API_SETUP.md for more information"
    Write-Host "  - If 500: check Portainer logs on the server (docker logs portainer)"
    exit 1
}
