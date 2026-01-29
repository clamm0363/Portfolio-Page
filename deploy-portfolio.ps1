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
    [string]$RepoUrl = "https://github.com/clamm0363/Portfolio-Page",
    
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

# ヘッダー設定
$headers = @{
    "X-API-Key" = $ApiToken
}

try {
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

    # 2. 既存のスタックを確認
    Write-Info "Checking for existing stacks..."
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $stacks = Invoke-RestMethod -Uri "$PortainerUrl/api/stacks" -Headers $headers -SkipCertificateCheck
    } else {
        $stacks = Invoke-RestMethod -Uri "$PortainerUrl/api/stacks" -Headers $headers
    }
    
    $existingStack = $stacks | Where-Object { $_.Name -eq $StackName }
    
    if ($existingStack) {
        Write-Info "Stack '$StackName' already exists. Deleting..."
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            Invoke-RestMethod -Uri "$PortainerUrl/api/stacks/$($existingStack.Id)" -Method Delete -Headers $headers -SkipCertificateCheck | Out-Null
        } else {
            Invoke-RestMethod -Uri "$PortainerUrl/api/stacks/$($existingStack.Id)" -Method Delete -Headers $headers | Out-Null
        }
        Write-Success "Existing stack deleted"
        Start-Sleep -Seconds 5
    }

    # 3. 環境変数の読み取り（.envファイルから）
    $envVars = @(
        @{ name = "UMAMI_DB_NAME"; value = "umami" }
        @{ name = "UMAMI_DB_USER"; value = "umami" }
    )
    
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
                    $envVars += @{ name = $key; value = $value }
                }
            }
        }
    } else {
        Write-Error-Custom ".env file not found! Using default values (NOT RECOMMENDED for production)"
        $envVars += @{ name = "UMAMI_DB_PASSWORD"; value = "FloYM2gp3ZGtKN9ADnPJxvsiEWuRhk45" }
        $envVars += @{ name = "UMAMI_HASH_SALT"; value = "54becf58b9d2c60dd2b53dfd36e683b0e72fb5d34c91d82bad4150f72cdd5ff4" }
    }

    # 4. 新しいStackを作成
    Write-Info "Creating new stack '$StackName'..."
    $body = @{
        name = $StackName
        repositoryURL = $RepoUrl
        repositoryReferenceName = "refs/heads/$Branch"
        composeFile = "docker-compose.yml"
        env = $envVars
    } | ConvertTo-Json -Depth 10

    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $response = Invoke-RestMethod `
            -Uri "$PortainerUrl/api/stacks?type=2&method=repository&endpointId=$endpointId" `
            -Method Post `
            -Headers $headers `
            -ContentType "application/json" `
            -Body $body `
            -SkipCertificateCheck
    } else {
        $response = Invoke-RestMethod `
            -Uri "$PortainerUrl/api/stacks?type=2&method=repository&endpointId=$endpointId" `
            -Method Post `
            -Headers $headers `
            -ContentType "application/json" `
            -Body $body
    }

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
    Write-Host "Error details:" -ForegroundColor Red
    Write-Host $_.Exception
    Write-Host ""
    Write-Info "Troubleshooting:"
    Write-Host "  - Check if Portainer is accessible at $PortainerUrl"
    Write-Host "  - Verify your API token is valid"
    Write-Host "  - Check PORTAINER_API_SETUP.md for more information"
    exit 1
}
