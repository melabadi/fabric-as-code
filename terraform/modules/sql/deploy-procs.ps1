#requires -Version 7.0
<#
.SYNOPSIS
  Deploy ordered .sql files to a Fabric Warehouse, called by the Terraform sql module.
.DESCRIPTION
  Resolves the Warehouse SQL endpoint via the Fabric REST API, then runs each
  .sql file (split on GO) using .NET SqlClient with an Entra access token from
  the current "az login" session. No sqlcmd dependency.
#>
param(
  [Parameter(Mandatory)] [string] $WorkspaceId,
  [Parameter(Mandatory)] [string] $WarehouseId,
  [Parameter(Mandatory)] [string] $Database,
  [Parameter(Mandatory)] [string] $SqlDir
)

$ErrorActionPreference = 'Stop'

function Get-Token([string] $Resource) {
  $t = az account get-access-token --resource $Resource --query accessToken -o tsv
  if (-not $t) { throw "Failed to get token for $Resource (is 'az login' done?)." }
  return $t
}

Write-Host "Resolving Warehouse SQL endpoint..." -ForegroundColor Cyan
$fabricToken = Get-Token 'https://api.fabric.microsoft.com'
$wh = Invoke-RestMethod -Method Get `
  -Uri "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/warehouses/$WarehouseId" `
  -Headers @{ Authorization = "Bearer $fabricToken" }
$server = $wh.properties.connectionString
if (-not $server) { throw 'Could not read Warehouse connectionString (still provisioning?).' }
Write-Host "  endpoint: $server / db: $Database"

$sqlToken = Get-Token 'https://database.windows.net/'

function Invoke-SqlFile([string] $Path) {
  $sql = Get-Content $Path -Raw
  $batches = [regex]::Split($sql, '(?im)^\s*GO\s*$') | Where-Object { $_.Trim() -ne '' }
  $conn = New-Object System.Data.SqlClient.SqlConnection
  $conn.ConnectionString = "Server=$server;Database=$Database;Encrypt=True;Connect Timeout=60;"
  $conn.AccessToken = $sqlToken
  $conn.Open()
  try {
    foreach ($b in $batches) {
      $cmd = $conn.CreateCommand(); $cmd.CommandText = $b; $cmd.CommandTimeout = 120
      [void] $cmd.ExecuteNonQuery()
    }
  } finally { $conn.Close() }
}

Get-ChildItem (Join-Path $SqlDir '*.sql') | Sort-Object Name | ForEach-Object {
  Write-Host "Executing $($_.Name)..." -ForegroundColor Cyan
  Invoke-SqlFile -Path $_.FullName
  Write-Host "  [ok] $($_.Name)" -ForegroundColor Green
}

Write-Host 'Stored procedures deployed.' -ForegroundColor Green
