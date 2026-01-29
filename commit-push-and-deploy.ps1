# 変更をコミット・プッシュし、Portainerで再デプロイするスクリプト
# 使い方: .\commit-push-and-deploy.ps1
# 注意: .env に PORTAINER_API_TOKEN が設定されている必要があります

$ErrorActionPreference = "Stop"
$repoRoot = $PSScriptRoot
Set-Location $repoRoot

Write-Host "=== 1. コミット・プッシュ ===" -ForegroundColor Cyan
git add index.html README.md CLOUDFLARE_TUNNEL_SETUP.md ANALYTICS_TROUBLESHOOTING.md CLOUDFLARE_ANALYTICS_ROUTE.md NPM_UMAMI_SETUP.md
git status
$msg = "Umami HTTPS化・analyticsサブドメイン対応 (index.html, README, 各種ドキュメント追加)"
git commit -m $msg
git push

Write-Host ""
Write-Host "=== 2. Portainerで再デプロイ ===" -ForegroundColor Cyan
if (-not (Test-Path ".env")) {
    Write-Host "エラー: .env が見つかりません" -ForegroundColor Red
    exit 1
}
$tokenLine = Get-Content ".env" | Where-Object { $_ -match "^PORTAINER_API_TOKEN=" }
if (-not $tokenLine) {
    Write-Host "エラー: .env に PORTAINER_API_TOKEN がありません" -ForegroundColor Red
    exit 1
}
$token = ($tokenLine -replace "PORTAINER_API_TOKEN=", "").Trim()
& "$repoRoot\deploy-portfolio.ps1" -ApiToken $token

Write-Host ""
Write-Host "Done." -ForegroundColor Green
