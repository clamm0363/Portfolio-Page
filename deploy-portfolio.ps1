#requires -Version 7.4
<#
.SYNOPSIS
Plan, apply, or verify a commit-pinned update of the existing Nginx service.
.DESCRIPTION
Plan is read-only. Apply changes exactly one Docker service through Portainer.
See DEPLOYMENT.md. Credentials are read from .env, never arguments.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Plan', 'Apply', 'Verify')][string]$Mode = 'Plan',
    [ValidatePattern('^[0-9a-f]{40}$')][string]$Commit,
    [ValidatePattern('^[0-9a-f]{40}$')][string]$PreviousCommit,
    [int]$EndpointId,
    [int]$StackId,
    [string]$StackName = 'portfolio-site',
    [string]$OriginUrl,
    [string]$PublicUrl = 'https://clamm-translation.net',
    [long]$ExpectedVersion = -1,
    [ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedSpecSha256,
    [switch]$Recovery,
    [ValidateRange(10, 900)][int]$TimeoutSeconds = 300
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PortfolioHash([byte[]]$Bytes) {
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Get-PortfolioSpecHash($Spec) {
    Get-PortfolioHash ([Text.Encoding]::UTF8.GetBytes(((ConvertTo-PortfolioCanonical $Spec) | ConvertTo-Json -Depth 100 -Compress)))
}

function ConvertTo-PortfolioCanonical($Value) {
    if ($Value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in $Value.Keys | Sort-Object) { $ordered[$key] = ConvertTo-PortfolioCanonical $Value[$key] }
        return $ordered
    }
    if ($Value -is [array]) {
        return ,@($Value | ForEach-Object { ConvertTo-PortfolioCanonical $_ })
    }
    $Value
}

function ConvertFrom-PortfolioCdnHtml([string]$Html) {
    # Only undo the two Cloudflare transformations observed on this site.
    $Html = [regex]::Replace($Html, 'href="/cdn-cgi/l/email-protection#([0-9a-f]+)"', {
        param($match)
        $bytes = [Convert]::FromHexString($match.Groups[1].Value)
        $decoded = [byte[]]@($bytes[1..($bytes.Length - 1)] | ForEach-Object { $_ -bxor $bytes[0] })
        'href="mailto:' + [Text.Encoding]::UTF8.GetString($decoded) + '"'
    })
    $Html = [regex]::Replace($Html, '<script\b[^>]*\bsrc="/cdn-cgi/scripts/[^"<>]+/cloudflare-static/email-decode\.min\.js"[^>]*></script>', '')
    $Html = [regex]::Replace($Html, '<script\b[^>]*\bsrc="https://static\.cloudflareinsights\.com/beacon\.min\.js/[^"<>]+"[^>]*></script>', '')
    ([regex]::Replace($Html, '\s+', ' ')).Trim()
}

function Read-PortfolioEnv([string]$Path) {
    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$') {
            $value = $Matches[2].Trim()
            if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'")))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $values[$Matches[1]] = $value
        }
    }
    $values
}

function Invoke-PortfolioApi([string]$Method, [string]$Path, $Body = $null) {
    $request = @{
        Uri = "$script:PortfolioBase/api/$Path"; Method = $Method
        Headers = @{ 'X-API-Key' = $script:PortfolioToken }
        TimeoutSec = 30; MaximumRedirection = 0
    }
    if ($null -ne $Body) {
        $request.ContentType = 'application/json'
        $request.Body = $Body | ConvertTo-Json -Depth 100 -Compress
    }
    try { $result = Invoke-RestMethod @request } catch {
        # API error bodies can contain credentials. Never echo them or retry a write.
        throw "Portainer $Method request failed. No automatic retry; inspect current state before continuing."
    }
    if ($null -ne $result) {
        ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $result -Depth 100 -Compress) -AsHashtable
    }
}

function Get-PortfolioBytes([string]$Url) {
    try {
        $response = Invoke-WebRequest -Uri $Url -Headers @{ 'Cache-Control' = 'no-cache' } -TimeoutSec 30 -MaximumRedirection 0
        return ,$response.RawContentStream.ToArray()
    } catch {
        throw 'Site/source download failed. No credentials or response body have been logged.'
    }
}

function Get-PortfolioArtifacts([string]$Sha) {
    $raw = "https://raw.githubusercontent.com/clamm0363/Portfolio-Page/$Sha"
    $index = Get-PortfolioBytes "$raw/index.html"
    $html = [Text.Encoding]::UTF8.GetString($index)
    $paths = @('index.html')
    foreach ($match in [regex]::Matches($html, '(?:src|href)=["'']/?(assets/[^"''?#]+)')) {
        $path = $match.Groups[1].Value
        if ($path -notmatch '^assets/[A-Za-z0-9_./-]+$' -or $path.Contains('..')) {
            throw 'Unsupported asset path. Review it before deployment.'
        }
        $paths += $path
    }
    $hashes = [ordered]@{ 'index.html' = Get-PortfolioHash $index }
    foreach ($path in $paths | Sort-Object -Unique | Where-Object { $_ -ne 'index.html' }) {
        $hashes[$path] = Get-PortfolioHash (Get-PortfolioBytes "$raw/$path")
    }
    $null = Get-PortfolioBytes "$raw/nginx/nginx.conf"
    $hashes
}

function Test-PortfolioOrigin([string]$Sha, $Hashes, [switch]$RequireMarker) {
    $nonce = [guid]::NewGuid().ToString('N')
    foreach ($path in $Hashes.Keys) {
        $actual = Get-PortfolioHash (Get-PortfolioBytes "$script:PortfolioOrigin/$path`?check=$nonce")
        if ($actual -ne $Hashes[$path]) { throw "Origin content mismatch: $path. Stop and inspect drift/cache." }
    }
    if ($RequireMarker) {
        $marker = [Text.Encoding]::UTF8.GetString((Get-PortfolioBytes "$script:PortfolioOrigin/release.json?check=$nonce")) | ConvertFrom-Json -AsHashtable
        if ($marker['commit'] -ne $Sha) { throw 'Origin release marker does not match the expected commit.' }
    }
}

function New-PortfolioSpec($Current, [string]$Sha) {
    $spec = $Current | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable
    $container = $spec.TaskTemplate.ContainerSpec
    $container.Command = @('/bin/sh')
    $container.Args = @('-ec', (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'scripts/start-site.sh') -Raw).Replace("`r`n", "`n"))
    $container.Env = @($container['Env'] | Where-Object { $_ -and $_ -notmatch '^PORTFOLIO_COMMIT=' }) + "PORTFOLIO_COMMIT=$Sha"
    $container.Healthcheck = @{
        Test = @('CMD-SHELL', 'wget -q -O - http://127.0.0.1/health | grep -qx healthy')
        Interval = 10000000000L; Timeout = 3000000000L; Retries = 3; StartPeriod = 60000000000L
    }
    if (-not $spec['UpdateConfig']) { $spec.UpdateConfig = @{} }
    $spec.UpdateConfig.Parallelism = 1
    $spec.UpdateConfig.Order = 'start-first'
    # The legacy PreviousSpec follows main; automatic rollback to it is unsafe.
    $spec.UpdateConfig.FailureAction = 'pause'
    $spec.UpdateConfig.Monitor = 30000000000L
    $spec.UpdateConfig.MaxFailureRatio = 0
    $spec
}

function Get-PortfolioRunningTasks([string]$ServiceId) {
    $filters = [uri]::EscapeDataString((@{ service = @($ServiceId); 'desired-state' = @('running') } | ConvertTo-Json -Compress))
    @(Invoke-PortfolioApi GET "endpoints/$EndpointId/docker/tasks?filters=$filters")
}

function Test-PortfolioConvergence($Service, [string]$Sha) {
    $tasks = @(Get-PortfolioRunningTasks $Service.ID)
    $replicas = $Service.Spec.Mode.Replicated.Replicas
    $state = if ($Service['UpdateStatus']) { $Service.UpdateStatus['State'] } else { '' }
    $tasks.Count -eq $replicas -and
        @($tasks | Where-Object { $_.Status.State -ne 'running' -or
            "PORTFOLIO_COMMIT=$Sha" -notin $_.Spec.ContainerSpec.Env }).Count -eq 0 -and
        $state -eq 'completed'
}

# Tests dot-source functions without loading .env or using the network.
if ($MyInvocation.InvocationName -eq '.') { return }
if (-not $Commit -or $EndpointId -lt 1 -or $StackId -lt 1 -or -not $OriginUrl) {
    throw 'Specify -Commit (full SHA), -EndpointId, -StackId and -OriginUrl; see DEPLOYMENT.md.'
}
if ($Mode -ne 'Verify' -and -not $PreviousCommit) { throw 'Plan/Apply requires a known deployed -PreviousCommit, not a moving branch.' }
if ($Mode -eq 'Apply' -and $ExpectedVersion -lt 0) { throw 'Apply requires the ExpectedVersion returned by Plan.' }
if ($Mode -eq 'Apply' -and -not $ExpectedSpecSha256) { throw 'Apply requires the ProposedSpecSha256 returned by Plan as -ExpectedSpecSha256.' }
# Caller refreshes origin/main before Plan; only commits adopted there may be served.
& git -C $PSScriptRoot merge-base --is-ancestor $Commit origin/main 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Commit is not in local origin/main. Fetch and confirm the adopted GitHub commit first.' }
$settings = Read-PortfolioEnv (Join-Path $PSScriptRoot '.env')
$script:PortfolioBase = $settings['PORTAINER_URL']
$script:PortfolioToken = $settings['PORTAINER_API_TOKEN']
if (-not $script:PortfolioBase -or -not $script:PortfolioToken) { throw '.env requires PORTAINER_URL and PORTAINER_API_TOKEN.' }
$script:PortfolioBase = $script:PortfolioBase.TrimEnd('/')
$script:PortfolioOrigin = $OriginUrl.TrimEnd('/')
foreach ($url in @($script:PortfolioBase, $script:PortfolioOrigin, $PublicUrl)) {
    $parsed = [uri]$url
    if (-not $parsed.IsAbsoluteUri -or $parsed.Scheme -notin @('http', 'https') -or $parsed.UserInfo -or $parsed.Query -or $parsed.Fragment) {
        throw 'Use absolute HTTP(S) base URLs without embedded credentials, query or fragment.'
    }
}
$stack = Invoke-PortfolioApi GET "stacks/$StackId"
if ($stack.EndpointId -ne $EndpointId -or $stack.Name -ne $StackName -or $stack.Type -ne 1 -or
    $stack.GitConfig.URL.TrimEnd('/').Replace('.git', '') -ne 'https://github.com/clamm0363/Portfolio-Page' -or
    $stack.GitConfig.ReferenceName -ne 'refs/heads/main' -or $stack['AutoUpdate']) {
    throw 'Stack identity/Git configuration mismatch or automatic Stack redeploy enabled. Stop and inspect.'
}
$services = @(Invoke-PortfolioApi GET "endpoints/$EndpointId/docker/services")
$matchingServices = @($services | Where-Object { $_.Spec.Name -eq "${StackName}_nginx" -and
    $_.Spec.Labels['com.docker.stack.namespace'] -eq $StackName })
if ($matchingServices.Count -ne 1) { throw 'Expected exactly one matching Nginx service.' }
$service = $matchingServices[0]
foreach ($mount in @($service.Spec.TaskTemplate.ContainerSpec['Mounts'])) {
    if ($mount -and ($mount.Target -eq '/' -or $mount.Target -match '^/(usr|etc)(/|$)' -or
        $mount.Target -eq '/tmp' -or $mount.Target -match '^/tmp/portfolio-source(/|$)')) {
        throw 'Unexpected mount over site/config/scratch paths. Do not overwrite mounted data.'
    }
}
if ($service.Spec.TaskTemplate.ContainerSpec.Image -notmatch '(^sha256:[0-9a-f]{64}$|@sha256:[0-9a-f]{64}$)' -or
    $service.Spec.Mode.Replicated.Replicas -lt 1) { throw 'Expected a digest-pinned replicated service.' }
if (-not $Recovery -and $service['UpdateStatus'] -and $service.UpdateStatus['State'] -in @('updating', 'paused', 'rollback_started', 'rollback_paused')) {
    throw 'Service has an unfinished update. Inspect it before starting another deployment.'
}
if (-not $Recovery -and $Mode -ne 'Verify') {
    $running = @(Get-PortfolioRunningTasks $service.ID)
    if ($running.Count -ne $service.Spec.Mode.Replicated.Replicas -or @($running | Where-Object { $_.Status.State -ne 'running' }).Count) {
        throw 'Existing Nginx tasks are not stable. Inspect state before deployment.'
    }
}
$targetArtifacts = Get-PortfolioArtifacts $Commit
if ($Mode -eq 'Verify') {
    if (-not (Test-PortfolioConvergence $service $Commit)) { throw 'Nginx tasks have not converged to the expected commit.' }
    Test-PortfolioOrigin $Commit $targetArtifacts -RequireMarker
} else {
    if (-not $Recovery) { Test-PortfolioOrigin $PreviousCommit (Get-PortfolioArtifacts $PreviousCommit) }
    $desired = New-PortfolioSpec $service.Spec $Commit
    [ordered]@{
        Mode = $Mode; StackId = $StackId; EndpointId = $EndpointId; Service = $service.Spec.Name
        ExpectedVersion = $service.Version.Index; PreviousCommit = $PreviousCommit; Commit = $Commit
        Recovery = [bool]$Recovery
        ImagePreserved = $service.Spec.TaskTemplate.ContainerSpec.Image
        CurrentSpecSha256 = Get-PortfolioSpecHash $service.Spec
        ProposedSpecSha256 = Get-PortfolioSpecHash $desired
        ArtifactPaths = @($targetArtifacts.Keys)
    } | ConvertTo-Json -Depth 5
    if ($Mode -eq 'Plan') { return }
    if ($service.Version.Index -ne $ExpectedVersion) { throw 'Service version changed since Plan. Generate and review a new plan.' }
    if ((Get-PortfolioSpecHash $desired) -ne $ExpectedSpecSha256) { throw 'Proposed spec changed since Plan. Regenerate and review the plan.' }
    if (-not $PSCmdlet.ShouldProcess($service.Spec.Name, "Update only Nginx to commit $Commit")) { return }
    # Optimistic concurrency: Docker rejects a stale service version. No POST retries.
    $null = Invoke-PortfolioApi POST "endpoints/$EndpointId/docker/services/$($service.ID)/update?version=$ExpectedVersion" $desired
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $current = Invoke-PortfolioApi GET "endpoints/$EndpointId/docker/services/$($service.ID)"
        if ((Get-PortfolioSpecHash $current.Spec) -ne (Get-PortfolioSpecHash $desired)) { throw 'Unexpected service spec after update. Stop; do not overwrite concurrent work.' }
        if ($current['UpdateStatus'] -and $current.UpdateStatus['State'] -in @('paused', 'rollback_started', 'rollback_paused', 'rollback_completed')) {
            throw 'Update did not complete. Inspect state; restore pinned PreviousCommit using a fresh Plan.'
        }
        if (Test-PortfolioConvergence $current $Commit) { break }
        Start-Sleep -Seconds 5
    } while ([DateTime]::UtcNow -lt $deadline)
    if (-not (Test-PortfolioConvergence $current $Commit)) { throw 'Timed out waiting for Nginx. Read current state before any further action.' }
    Test-PortfolioOrigin $Commit $targetArtifacts -RequireMarker
    $after = @(Invoke-PortfolioApi GET "endpoints/$EndpointId/docker/services")
    foreach ($other in $services | Where-Object { $_.ID -ne $service.ID }) {
        $now = @($after | Where-Object { $_.ID -eq $other.ID })
        if ($now.Count -ne 1 -or (Get-PortfolioSpecHash $now[0].Spec) -ne (Get-PortfolioSpecHash $other.Spec)) {
            throw 'Another service changed during deployment. Investigate; do not automatically revert it.'
        }
    }
}
# Cloudflare transforms HTML. Compare origin bytes, then public marker/title/assets.
$nonce = [guid]::NewGuid().ToString('N')
$publicMarker = [Text.Encoding]::UTF8.GetString((Get-PortfolioBytes "$($PublicUrl.TrimEnd('/'))/release.json?check=$nonce")) | ConvertFrom-Json -AsHashtable
if ($publicMarker['commit'] -ne $Commit) { throw 'Public release marker is stale or mismatched.' }
$publicHtml = [Text.Encoding]::UTF8.GetString((Get-PortfolioBytes "$($PublicUrl.TrimEnd('/'))/?check=$nonce"))
$sourceHtml = [Text.Encoding]::UTF8.GetString((Get-PortfolioBytes "https://raw.githubusercontent.com/clamm0363/Portfolio-Page/$Commit/index.html"))
if ((ConvertFrom-PortfolioCdnHtml $publicHtml) -ne (ConvertFrom-PortfolioCdnHtml $sourceHtml)) {
    throw 'Public HTML differs after accounting for known Cloudflare transformations. Inspect cache/content before completion.'
}
foreach ($path in $targetArtifacts.Keys | Where-Object { $_ -ne 'index.html' }) {
    if ((Get-PortfolioHash (Get-PortfolioBytes "$($PublicUrl.TrimEnd('/'))/$path`?check=$nonce")) -ne $targetArtifacts[$path]) {
        throw "Public asset mismatch: $path. Inspect CDN cache before marking deployment complete."
    }
}
Write-Output "Verified commit $Commit at origin and public URL. Browser display/links still require visual confirmation."
