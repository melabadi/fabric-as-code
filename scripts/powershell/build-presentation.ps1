#requires -Version 7.0
param(
    [string] $Source = (Join-Path $PSScriptRoot '../../docs/presentation.md'),
    [string] $OutputDirectory = (Join-Path $PSScriptRoot '../../docs')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$npmCommand = Get-Command npm.cmd -All -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty Source
if ([string]::IsNullOrWhiteSpace($npmCommand)) {
    throw 'npm is required to render the presentation. Install Node.js 22 or later.'
}

$sourcePath = (Resolve-Path $Source).Path
$outputPath = (Resolve-Path $OutputDirectory).Path
$marpPackage = '@marp-team/marp-cli@4.5.0'

function Invoke-MarpRender {
    param(
        [Parameter(Mandatory)] [ValidateSet('pdf', 'pptx')] [string] $Format,
        [Parameter(Mandatory)] [string] $Target
    )

    $arguments = @(
        'exec'
        '--yes'
        "--package=$marpPackage"
        '--'
        'marp'
        $sourcePath
        "--$Format"
        '--output'
        $Target
    )
    & $npmCommand @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Marp $Format rendering failed."
    }
    if (-not (Test-Path -LiteralPath $Target -PathType Leaf) -or
        (Get-Item -LiteralPath $Target).Length -eq 0) {
        throw "Marp did not create '$Target'."
    }
}

$pptxPath = Join-Path $outputPath 'Fabric-as-Code.pptx'
$pdfPath = Join-Path $outputPath 'Fabric-as-Code.pdf'

Invoke-MarpRender -Format pptx -Target $pptxPath
Invoke-MarpRender -Format pdf -Target $pdfPath

[pscustomobject]@{
    source = $sourcePath
    pptx   = $pptxPath
    pdf    = $pdfPath
} | ConvertTo-Json
