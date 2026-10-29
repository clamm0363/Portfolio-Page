# Offline contract tests. No real credentials, HTTP requests or service writes.
#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$entry = Join-Path $root 'deploy-portfolio.ps1'
. $entry
$global:PortfolioTest_passed = 0
function Assert-Check($Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $global:PortfolioTest_passed++
}
function Assert-Fails([scriptblock]$Action, [string]$Pattern) {
    $failed = $false
    try { $null = & $Action } catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        $failed = $true
    }
    Assert-Check $failed "expected failure: $Pattern"
}
function Reset-Fixture {
    $global:PortfolioTest_calls = [Collections.Generic.List[object]]::new()
    $global:PortfolioTest_posted = $false
    $global:PortfolioTest_throwPost = $false
    $global:PortfolioTest_badOrigin = $false
    $global:PortfolioTest_badPublic = $false
    $global:PortfolioTest_badTasks = $false
    $global:PortfolioTest_autoUpdate = $null
    $global:PortfolioTest_fixtureHtml = '<html><head><title>Masaru Funahashi | Game Translator Portfolio</title></head><body><img src="assets/images/test.png"><a href="mailto:a@b.example" class="contact">Email</a></body></html>'
    $global:PortfolioTest_sha = '60eed70e56f543fea918b951cb112d3c6933d71a'
    $global:PortfolioTest_svc = @{
        ID = 'test-nginx'; Version = @{ Index = 42 }
        Spec = @{
            Name = 'portfolio-site_nginx'; Labels = @{ 'com.docker.stack.namespace' = 'portfolio-site' }
            TaskTemplate = @{ ContainerSpec = @{ Image = 'sha256:' + ('a' * 64); Env = @('KEEP_ME=synthetic'); Args = @('legacy'); Command = @('/bin/sh') }; Networks = @(@{Target='preserve-network'}) }
            Mode = @{ Replicated = @{ Replicas = 1 } }; EndpointSpec = @{ Ports = @(@{ PublishedPort = 8001; TargetPort = 80 }) }
        }
    }
    $global:PortfolioTest_other = @{ ID = 'test-umami'; Spec = @{ Name = 'portfolio-site_umami'; TaskTemplate = @{ ContainerSpec = @{ Image = 'sha256:' + ('b' * 64); Env = @('DATABASE_URL=synthetic-only') } } } }
}
# Replace only .env reads; every other file comes from the real workspace.
function Get-Content {
    param([string]$LiteralPath, [string]$Path, [switch]$Raw)
    $file = if ($LiteralPath) { $LiteralPath } else { $Path }
    if ((Split-Path $file -Leaf) -eq '.env') {
        return @('PORTAINER_URL=http://portainer.invalid', 'PORTAINER_API_TOKEN=synthetic-test-token')
    }
    Microsoft.PowerShell.Management\Get-Content -LiteralPath $file -Raw:$Raw
}
function Invoke-RestMethod {
    param($Uri, $Method, $Headers, $TimeoutSec, $MaximumRedirection, $ContentType, $Body)
    $global:PortfolioTest_calls.Add(@{ Method = $Method; Uri = $Uri })
    $path = ([uri]$Uri).AbsolutePath
    if ($Method -eq 'POST') {
        if ($path -ne '/api/endpoints/3/docker/services/test-nginx/update') { throw 'Unexpected write target' }
        if ($global:PortfolioTest_throwPost) { throw 'synthetic-secret-in-error-body' }
        $global:PortfolioTest_svc.Spec = $Body | ConvertFrom-Json -AsHashtable
        $global:PortfolioTest_svc.Version.Index++
        $global:PortfolioTest_svc.UpdateStatus = @{ State = 'completed' }
        $global:PortfolioTest_posted = $true
        return @{}
    }
    switch ($path) {
        '/api/stacks/36' { return @{ Id=36; Name='portfolio-site'; EndpointId=3; Type=1; GitConfig=@{URL='https://github.com/clamm0363/Portfolio-Page';ReferenceName='refs/heads/main'}; AutoUpdate=$global:PortfolioTest_autoUpdate } }
        '/api/endpoints/3/docker/services' { return @($global:PortfolioTest_svc, $global:PortfolioTest_other) }
        '/api/endpoints/3/docker/services/test-nginx' { return $global:PortfolioTest_svc }
        '/api/endpoints/3/docker/tasks' {
            return @{ ID='task'; Status=@{State= $(if($global:PortfolioTest_badTasks){'preparing'}else{'running'})}; Spec=@{ContainerSpec=@{Env=@("PORTFOLIO_COMMIT=$global:PortfolioTest_sha")}} }
        }
        default { throw 'Unexpected mock API path' }
    }
}
function Invoke-WebRequest {
    param($Uri, $Headers, $TimeoutSec, $MaximumRedirection)
    $url = [uri]$Uri
    $path = $url.AbsolutePath
    $body = if ($path.EndsWith('/release.json')) { '{"commit":"' + $global:PortfolioTest_sha + '"}' }
        elseif ($path.EndsWith('/nginx/nginx.conf')) { 'synthetic nginx configuration' }
        elseif ($path.EndsWith('.png')) { 'synthetic image bytes' }
        elseif ($url.Host -eq 'origin.invalid' -and $global:PortfolioTest_badOrigin -and -not $global:PortfolioTest_posted) { 'unrecorded origin content' }
        elseif ($url.Host -eq 'public.invalid' -and $global:PortfolioTest_badPublic) { 'stale public HTML' }
        else { $global:PortfolioTest_fixtureHtml }
    @{ RawContentStream = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($body)) }
}
function Invoke-Fixture([string]$Operation, [hashtable]$Extra = @{}) {
    & $entry -Mode $Operation -Commit $global:PortfolioTest_sha -PreviousCommit $global:PortfolioTest_sha -EndpointId 3 -StackId 36 `
        -OriginUrl 'http://origin.invalid:8001' -PublicUrl 'https://public.invalid' @Extra
}
function Get-FixtureApproval {
    @{ ExpectedVersion = 42; ExpectedSpecSha256 = (Get-PortfolioSpecHash (New-PortfolioSpec $global:PortfolioTest_svc.Spec $global:PortfolioTest_sha)) }
}

Reset-Fixture
$plan = Invoke-Fixture Plan | ConvertFrom-Json
Assert-Check ($plan.ExpectedVersion -eq 42 -and $plan.ArtifactPaths.Count -eq 2) 'Plan identifies version and assets'
Assert-Check (@($global:PortfolioTest_calls | Where-Object Method -ne GET).Count -eq 0) 'Plan never writes'
$before = Get-PortfolioSpecHash $global:PortfolioTest_svc.Spec
$desired = New-PortfolioSpec $global:PortfolioTest_svc.Spec $global:PortfolioTest_sha
Assert-Check ((Get-PortfolioSpecHash $global:PortfolioTest_svc.Spec) -eq $before) 'candidate does not mutate source spec'
Assert-Check ($desired.TaskTemplate.ContainerSpec.Image -eq $global:PortfolioTest_svc.Spec.TaskTemplate.ContainerSpec.Image) 'live image preserved'
Assert-Check ('KEEP_ME=synthetic' -in $desired.TaskTemplate.ContainerSpec.Env) 'unrelated environment preserved'
Assert-Check ($desired.TaskTemplate.Networks[0].Target -eq 'preserve-network' -and $desired.EndpointSpec.Ports[0].PublishedPort -eq 8001) 'network and ports preserved'
Assert-Check ($desired.UpdateConfig.Order -eq 'start-first' -and $desired.UpdateConfig.FailureAction -eq 'pause') 'safe update policy'
Assert-Check ((Get-PortfolioSpecHash @{a=1;b=@{x=2;y=3}}) -eq (Get-PortfolioSpecHash @{b=@{y=3;x=2};a=1})) 'spec hashing ignores dictionary order'

Reset-Fixture
$null = Invoke-Fixture Apply (Get-FixtureApproval)
Assert-Check (@($global:PortfolioTest_calls | Where-Object Method -eq POST).Count -eq 1) 'successful apply writes exactly one service once'
Assert-Check ($global:PortfolioTest_svc.Spec.TaskTemplate.ContainerSpec.Env -contains "PORTFOLIO_COMMIT=$global:PortfolioTest_sha") 'applied commit pinned'
Assert-Check ($global:PortfolioTest_other.Spec.TaskTemplate.ContainerSpec.Env[0] -eq 'DATABASE_URL=synthetic-only') 'Umami not changed'
$null = Invoke-Fixture Verify
Assert-Check (@($global:PortfolioTest_calls | Where-Object Method -eq POST).Count -eq 1) 'Verify is read-only'

Reset-Fixture
$approval = Get-FixtureApproval; $approval.WhatIf = $true
$null = Invoke-Fixture Apply $approval
Assert-Check (@($global:PortfolioTest_calls | Where-Object Method -eq POST).Count -eq 0) 'WhatIf never writes'

Reset-Fixture
Assert-Fails { Invoke-Fixture Apply } 'ExpectedVersion'
$approval = Get-FixtureApproval; $approval.ExpectedVersion = 41
Assert-Fails { Invoke-Fixture Apply $approval } 'version changed'
$approval = Get-FixtureApproval; $approval.ExpectedSpecSha256 = '0' * 64
Assert-Fails { Invoke-Fixture Apply $approval } 'spec changed'
Assert-Check (@($global:PortfolioTest_calls | Where-Object Method -eq POST).Count -eq 0) 'stale/unapproved plans blocked before write'

Reset-Fixture
$global:PortfolioTest_badOrigin = $true
Assert-Fails { Invoke-Fixture Plan } 'Origin content mismatch'
Assert-Check (@($global:PortfolioTest_calls | Where-Object Method -eq POST).Count -eq 0) 'origin drift blocks apply'
$global:PortfolioTest_svc.UpdateStatus = @{State='paused'}
Assert-Fails { Invoke-Fixture Plan } 'unfinished update'
$recoveryPlanResult = Invoke-Fixture Plan @{Recovery=$true} | ConvertFrom-Json
Assert-Check $recoveryPlanResult.Recovery 'recovery plan explicitly marked'
$approval = Get-FixtureApproval; $approval.Recovery = $true
$null = Invoke-Fixture Apply $approval
Assert-Check $global:PortfolioTest_posted 'recovery can restore a paused update'

Reset-Fixture
$global:PortfolioTest_autoUpdate = @{Interval='5m'}
Assert-Fails { Invoke-Fixture Plan } 'automatic Stack redeploy'
Reset-Fixture
$global:PortfolioTest_svc.Spec.TaskTemplate.ContainerSpec.Image = 'nginx:latest'
Assert-Fails { Invoke-Fixture Plan } 'digest-pinned'
Reset-Fixture
$global:PortfolioTest_svc.Spec.TaskTemplate.ContainerSpec.Mounts = @(@{Target='/usr/share/nginx/html'})
Assert-Fails { Invoke-Fixture Plan } 'mounted data'
foreach ($scratchMount in @('/tmp', '/tmp/portfolio-source', '/tmp/portfolio-source/nested')) {
    Reset-Fixture
    $global:PortfolioTest_svc.Spec.TaskTemplate.ContainerSpec.Mounts = @(@{Target=$scratchMount})
    Assert-Fails { Invoke-Fixture Plan } 'mounted data'
}
Reset-Fixture
$global:PortfolioTest_badTasks = $true
Assert-Fails { Invoke-Fixture Plan } 'not stable'

Reset-Fixture
$global:PortfolioTest_throwPost = $true
Assert-Fails { Invoke-Fixture Apply (Get-FixtureApproval) } '^Portainer POST request failed'
Assert-Check (@($global:PortfolioTest_calls | Where-Object Method -eq POST).Count -eq 1) 'ambiguous POST failure never retried'
Reset-Fixture
$global:PortfolioTest_badPublic = $true
Assert-Fails { Invoke-Fixture Apply (Get-FixtureApproval) } 'Public HTML differs'
Assert-Check (@($global:PortfolioTest_calls | Where-Object Method -eq POST).Count -eq 1) 'public verification failure does not write again'

$plain = '<a href="mailto:a@b.example" class="x">Contact</a><script>app()</script>'
$encoded = '01' + [Convert]::ToHexString([byte[]]@([Text.Encoding]::UTF8.GetBytes('a@b.example') | ForEach-Object { $_ -bxor 1 })).ToLowerInvariant()
$cdn = '<a href="/cdn-cgi/l/email-protection#' + $encoded + '"' + "`n" + 'class="x">Contact</a><script data-cfasync="false" src="/cdn-cgi/scripts/abc/cloudflare-static/email-decode.min.js"></script><script>app()</script><script type="module" src="https://static.cloudflareinsights.com/beacon.min.js/test" data-cf-beacon="synthetic"></script>'
Assert-Check ((ConvertFrom-PortfolioCdnHtml $cdn) -eq (ConvertFrom-PortfolioCdnHtml $plain)) 'known Cloudflare transforms accounted for'
Assert-Check ((ConvertFrom-PortfolioCdnHtml ($plain.Replace('app()', 'wrong()'))) -ne (ConvertFrom-PortfolioCdnHtml $plain)) 'application script changes remain visible'
Write-Output "PASS: $global:PortfolioTest_passed offline deployment checks; no network or real credentials used."
