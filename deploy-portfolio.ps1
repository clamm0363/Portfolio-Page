# Portfolio Site Deployment Script for Portainer (Docker Swarm Stack)
# Usage: .\deploy-portfolio.ps1 -ApiToken "ptr_your_token_here"

param(
    [Parameter(Mandatory=$false)]
    [string]$ApiToken,
    
    [Parameter(Mandatory=$false)]
    [string]$PortainerUrl,
    
    [Parameter(Mandatory=$false)]
    [string]$StackName = "portfolio-site",
    
    [Parameter(Mandatory=$false)]
    [string]$RepoUrl = "https://github.com/clamm0363/Portfolio-Page",
    
    [Parameter(Mandatory=$false)]
    [string]$Branch = "main"
)

# Fix for Japanese text encoding (prevents garbled characters)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Colors for output
$Green = "`e[32m"
$Red = "`e[31m"
$Yellow = "`e[33m"
$Blue = "`e[34m"
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

function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "${Blue}═══ $Message ═══${Reset}"
    Write-Host ""
}

# .envファイルから環境変数を読み込む
function Load-EnvFile {
    param([string]$FilePath = ".env")
    
    $envVars = @{}
    
    if (-not (Test-Path $FilePath)) {
        Write-Error-Custom ".env file not found at $FilePath"
        Write-Info "Please copy .env.example to .env and configure it"
        exit 1
    }
    
    Write-Info "Reading environment variables from $FilePath..."
    $envContent = Get-Content $FilePath | Where-Object { $_ -notmatch "^#" -and $_ -match "=" }
    
    foreach ($line in $envContent) {
        $parts = $line -split "=", 2
        if ($parts.Length -eq 2) {
            $key = $parts[0].Trim()
            $value = $parts[1].Trim()
            $envVars[$key] = $value
        }
    }
    
    return $envVars
}

# 環境変数の読み込み
$envVars = Load-EnvFile

# APIトークンの設定（パラメータ優先、なければ.envから）
if (-not $ApiToken) {
    if ($envVars.ContainsKey("PORTAINER_API_TOKEN")) {
        $ApiToken = $envVars["PORTAINER_API_TOKEN"]
        Write-Info "Using PORTAINER_API_TOKEN from .env file"
    } else {
        Write-Error-Custom "API Token is required!"
        Write-Info "Provide it via -ApiToken parameter or PORTAINER_API_TOKEN in .env file"
        exit 1
    }
}

# Portainer URLの設定
if (-not $PortainerUrl) {
    if ($envVars.ContainsKey("PORTAINER_URL")) {
        $PortainerUrl = $envVars["PORTAINER_URL"]
    } else {
        $PortainerUrl = "http://192.168.0.95:9000"
    }
}

Write-Info "Portainer URL: $PortainerUrl"

# 必須環境変数のチェック
$requiredVars = @("TUNNEL_TOKEN", "POSTGRES_PASSWORD", "UMAMI_HASH_SALT")
$missingVars = @()

foreach ($var in $requiredVars) {
    if (-not $envVars.ContainsKey($var) -or [string]::IsNullOrWhiteSpace($envVars[$var])) {
        $missingVars += $var
    }
}

if ($missingVars.Count -gt 0) {
    Write-Error-Custom "Missing required environment variables in .env file:"
    foreach ($var in $missingVars) {
        Write-Host "  - $var" -ForegroundColor Red
    }
    Write-Info "Please update your .env file with all required variables"
    exit 1
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

# ヘッダー設定
$headers = @{
    "X-API-Key" = $ApiToken
}

try {
    Write-Header "Deploying Portfolio to Docker Swarm Stack"
    
    Write-Info "Connecting to Portainer at $PortainerUrl..."
    
    # 1. エンドポイントIDを取得
    Write-Info "Fetching endpoint ID..."
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $endpoints = Invoke-RestMethod -Uri "$PortainerUrl/api/endpoints" -Headers $headers -SkipCertificateCheck
    } else {
        $endpoints = Invoke-RestMethod -Uri "$PortainerUrl/api/endpoints" -Headers $headers
    }
    
    $endpointId = $endpoints[0].Id
    Write-Success "Endpoint ID: $endpointId"

    # 2. 既存のスタックを確認とSwarm ID取得
    Write-Info "Checking for existing stacks..."
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $stacks = Invoke-RestMethod -Uri "$PortainerUrl/api/stacks" -Headers $headers -SkipCertificateCheck
    } else {
        $stacks = Invoke-RestMethod -Uri "$PortainerUrl/api/stacks" -Headers $headers
    }
    
    # Swarm IDを既存のSwarm Stackから取得
    $swarmId = ""
    $swarmStack = $stacks | Where-Object { $_.Type -eq 1 -and $_.SwarmId } | Select-Object -First 1
    if ($swarmStack) {
        $swarmId = $swarmStack.SwarmId
        Write-Success "Swarm ID obtained: $swarmId"
    } else {
        Write-Error-Custom "No existing Swarm stack found to get Swarm ID"
        Write-Info "Please create at least one Swarm stack manually first, or check Docker Swarm status"
        exit 1
    }
    
    # 旧スタック portfolio-site-new を自動削除（ポート競合回避）
    $oldStack = $stacks | Where-Object { $_.Name -eq "portfolio-site-new" }
    if ($oldStack) {
        Write-Info "Found old stack 'portfolio-site-new' (ID: $($oldStack.Id)). Removing to avoid port conflict..."
        $deleteUrl = "$PortainerUrl/api/stacks/$($oldStack.Id)?endpointId=$endpointId"
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            Invoke-RestMethod -Uri $deleteUrl -Method Delete -Headers $headers -SkipCertificateCheck | Out-Null
        } else {
            Invoke-RestMethod -Uri $deleteUrl -Method Delete -Headers $headers | Out-Null
        }
        Write-Success "Old stack 'portfolio-site-new' deleted"
        Write-Info "Waiting for port 8001 to be released..."
        Start-Sleep -Seconds 10
    }
    
    $existingStack = $stacks | Where-Object { $_.Name -eq $StackName }
    
    if ($existingStack) {
        Write-Info "Stack '$StackName' already exists. Deleting..."
        $deleteUrl = "$PortainerUrl/api/stacks/$($existingStack.Id)?endpointId=$endpointId"
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            Invoke-RestMethod -Uri $deleteUrl -Method Delete -Headers $headers -SkipCertificateCheck | Out-Null
        } else {
            Invoke-RestMethod -Uri $deleteUrl -Method Delete -Headers $headers | Out-Null
        }
        Write-Success "Existing stack deleted"
        Write-Info "Waiting for cleanup..."
        Start-Sleep -Seconds 5
    }

    # 3. Portainer API用の環境変数配列を作成
    Write-Info "Preparing environment variables for Swarm Stack..."
    $portainerEnvVars = @()
    
    # 必須環境変数
    $stackEnvVars = @(
        "POSTGRES_DB",
        "POSTGRES_USER", 
        "POSTGRES_PASSWORD",
        "UMAMI_HASH_SALT",
        "TUNNEL_TOKEN"
    )
    
    foreach ($varName in $stackEnvVars) {
        if ($envVars.ContainsKey($varName)) {
            $portainerEnvVars += @{ 
                name = $varName
                value = $envVars[$varName] 
            }
        } else {
            # デフォルト値を設定（DB名とユーザー）
            if ($varName -eq "POSTGRES_DB" -or $varName -eq "POSTGRES_USER") {
                $portainerEnvVars += @{ 
                    name = $varName
                    value = "umami" 
                }
            }
        }
    }
    
    Write-Success "Environment variables prepared: $($portainerEnvVars.Count) variables"

    # 4. 新しいStackを作成（Swarm Stack用）
    Write-Info "Creating new Swarm Stack '$StackName'..."
    $body = @{
        Name = $StackName
        RepositoryURL = $RepoUrl
        RepositoryReferenceName = "refs/heads/$Branch"
        ComposeFile = "docker-compose.yml"
        Env = $portainerEnvVars
        SwarmID = $swarmId
    } | ConvertTo-Json -Depth 10

    # Portainer 2.x系の新しいエンドポイントを使用
    $apiUrl = "$PortainerUrl/api/stacks/create/swarm/repository?endpointId=$endpointId"
    
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $response = Invoke-RestMethod `
            -Uri $apiUrl `
            -Method Post `
            -Headers $headers `
            -ContentType "application/json" `
            -Body $body `
            -SkipCertificateCheck
    } else {
        $response = Invoke-RestMethod `
            -Uri $apiUrl `
            -Method Post `
            -Headers $headers `
            -ContentType "application/json" `
            -Body $body
    }

    Write-Success "Stack created successfully!"
    Write-Success "Stack ID: $($response.Id)"
    
    Write-Header "Deployment Complete"
    
    Write-Success "Portfolio site deployment initiated!"
    Write-Host ""
    Write-Info "Stack Name: $StackName"
    Write-Info "Repository: $RepoUrl"
    Write-Info "Branch: $Branch"
    Write-Host ""
    Write-Info "Services deployed:"
    Write-Host "  • nginx (Swarm Service)"
    Write-Host "  • umami (Swarm Service)"
    Write-Host "  • umami-db (PostgreSQL)"
    Write-Host "  • cloudflared (Cloudflare Tunnel)"
    Write-Host ""
    Write-Info "Your portfolio site will be accessible via:"
    Write-Host "  🌐 Public URL: https://clamm-translation.net (via Cloudflare Tunnel)"
    Write-Host "  📊 Umami:      http://<node-ip>:3002"
    Write-Host ""
    Write-Info "To check deployment status, run:"
    Write-Host "  docker stack ps portfolio"
    Write-Host "  docker stack services portfolio"
    Write-Host "  docker service logs portfolio_nginx"
    Write-Host "  docker service logs portfolio_cloudflared"
    Write-Host ""
    Write-Info "Next steps:"
    Write-Host "  1. Wait 2-3 minutes for all services to start"
    Write-Host "  2. Check service status: docker stack ps portfolio"
    Write-Host "  3. Access your site via Cloudflare Tunnel"
    Write-Host "  4. Configure Umami at http://<node-ip>:3002 (admin/umami)"
    Write-Host ""
    
} catch {
    Write-Error-Custom "Deployment failed: $($_.Exception.Message)"
    Write-Host ""
    Write-Host "Error details:" -ForegroundColor Red
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $reader.BaseStream.Position = 0
        $responseBody = $reader.ReadToEnd()
        Write-Host $responseBody -ForegroundColor Red
    } else {
        Write-Host $_.Exception
    }
    Write-Host ""
    Write-Info "Troubleshooting:"
    Write-Host "  • Check if Portainer is accessible at $PortainerUrl"
    Write-Host "  • Verify your API token is valid (check .env file)"
    Write-Host "  • Ensure all required environment variables are set in .env"
    Write-Host "  • Check Docker Swarm is initialized: docker node ls"
    Write-Host "  • Verify 'public' network exists: docker network ls"
    Write-Host "  • Check DEPLOYMENT.md for more information"
    Write-Host ""
    exit 1
}
