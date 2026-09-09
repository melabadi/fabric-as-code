#requires -Version 7.0
param(
    [string] $RepositoryRoot = (Join-Path $PSScriptRoot '../..')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryPath = (Resolve-Path $RepositoryRoot).Path
$violations = [Collections.Generic.List[string]]::new()

Push-Location $repositoryPath
try {
    $trackedFiles = @(git ls-files)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to enumerate tracked files.'
    }

    $forbiddenPaths = @(
        '.github/public-sync/'
        '.github/workflows/publish-public.yml'
        'docs/MCAPS_FABRIC_RUNNER_EXAMPLE_LINKS.md'
        'docs/screenshots/'
        'scripts/powershell/export-public-repository.ps1'
    )
    foreach ($path in $trackedFiles) {
        if (@($forbiddenPaths | Where-Object {
                    $path -ceq $_ -or ($_.EndsWith('/') -and $path.StartsWith($_, [StringComparison]::Ordinal))
                }).Count -gt 0) {
            $violations.Add("Tracked private publication path: $path")
        }
    }

    $allowedGeneratedArtifacts = @(
        'docs/Fabric-as-Code.pdf'
        'docs/Fabric-as-Code.pptx'
    )
    $forbiddenArtifacts = @($trackedFiles | Where-Object {
            $_ -match '(?i)(^|/)(\.env|[^/]+\.tfstate(?:\..*)?|[^/]+\.tfplan|[^/]+\.(?:pem|pfx|key|token|pdf|pptx|png|jpe?g|gif|webp))$' -and
            $_ -notin $allowedGeneratedArtifacts
        })
    foreach ($path in $forbiddenArtifacts) {
        $violations.Add("Tracked private or binary evidence artifact: $path")
    }

    foreach ($path in @($trackedFiles | Where-Object { $_ -match '^terraform/environments/[^/]+\.tfvars$' })) {
        $header = @(Get-Content -LiteralPath $path -TotalCount 20)
        if (-not @($header | Where-Object { $_.Trim() -ceq '# deployment: template' })) {
            $violations.Add("Public environment file is not marked as a template: $path")
        }
    }

    $allowedGuids = @(
        '61d6811f-7544-4e75-a1e6-1c59c0383311'
        '11111111-1111-4111-8111-111111111111'
        '22222222-2222-4222-8222-222222222222'
        '33333333-3333-4333-8333-333333333333'
    )
    $allowedGheHosts = @('auth.ghe.com', 'example.ghe.com')
    $privateIdentityPatterns = [ordered]@{
        'Private GitHub organization marker' = '(?i)\bGHU-Recap\b'
        'Private GitHub account marker'      = '(?i)\bmehdilabadi_microsoft\b'
        'Private repository marker'          = '(?i)\bfabric-cicd\b'
    }
    $guidPattern = '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}'
    $gheHostPattern = '(?i)(?:[a-z0-9-]+\.)+ghe\.com'
    foreach ($path in $trackedFiles) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        if ($path -in $allowedGeneratedArtifacts) { continue }
        $lineNumber = 0
        foreach ($line in Get-Content -LiteralPath $path -ErrorAction SilentlyContinue) {
            $lineNumber++
            foreach ($match in [regex]::Matches($line, $guidPattern)) {
                $guid = $match.Value.ToLowerInvariant()
                if ($guid -match '^00000000-0000-0000-0000-0000000000[0-9a-f]{2}$') { continue }
                if ($guid -in $allowedGuids) { continue }
                $violations.Add("Non-synthetic GUID in ${path}:$lineNumber")
            }

            if ($line -match 'app\.fabric\.microsoft\.com/groups/[0-9A-Fa-f-]+') {
                $violations.Add("Concrete Fabric workspace URL in ${path}:$lineNumber")
            }
            if ($line -match '/subscriptions/[0-9A-Fa-f-]+/resourceGroups/') {
                $violations.Add("Concrete Azure resource ID in ${path}:$lineNumber")
            }
            foreach ($entry in $privateIdentityPatterns.GetEnumerator()) {
                if ($line -match $entry.Value) {
                    $violations.Add("$($entry.Key) in ${path}:$lineNumber")
                }
            }
            foreach ($match in [regex]::Matches($line, $gheHostPattern)) {
                if ($match.Value.ToLowerInvariant() -notin $allowedGheHosts) {
                    $violations.Add("Non-example dedicated GHE hostname in ${path}:$lineNumber")
                }
            }
        }
    }
} finally {
    Pop-Location
}

if ($violations.Count -gt 0) {
    $violations | Sort-Object -Unique | ForEach-Object { Write-Error $_ }
    throw "Public repository hygiene found $($violations.Count) violation(s)."
}

Write-Host 'Public repository hygiene checks passed.' -ForegroundColor Green
