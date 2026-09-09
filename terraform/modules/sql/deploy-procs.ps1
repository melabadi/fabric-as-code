#requires -Version 7.0
<#
.SYNOPSIS
  Deploy ordered .sql files to a Fabric Warehouse, called by the Terraform sql module.
.DESCRIPTION
  Runs each .sql file (split on GO) against the provider-resolved Warehouse SQL
  endpoint using .NET SqlClient with an Entra access token from the current
  "az login" session. No sqlcmd dependency.
#>
param(
  [Parameter(Mandatory)] [string] $Server,
  [Parameter(Mandatory)] [string] $Database,
  [Parameter(Mandatory)] [string] $SqlDir
)

$ErrorActionPreference = 'Stop'

$sqlToken = az account get-access-token --resource 'https://database.windows.net/' --query accessToken -o tsv
if (-not $sqlToken) { throw "Failed to get a SQL access token (is 'az login' done?)." }
Write-Host "Deploying to endpoint: $Server / db: $Database" -ForegroundColor Cyan

function Invoke-SqlFile([string] $Path) {
  $sql = Get-Content $Path -Raw
  $batches = [regex]::Split($sql, '(?im)^\s*GO\s*$') | Where-Object { $_.Trim() -ne '' }
  $conn = New-Object System.Data.SqlClient.SqlConnection
  $conn.ConnectionString = "Server=$Server;Database=$Database;Encrypt=True;Connect Timeout=60;"
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
