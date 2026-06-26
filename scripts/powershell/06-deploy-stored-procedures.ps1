# =============================================================================
# 06-deploy-stored-procedures.ps1 — deploy schema, tables and stored procedures
# to the Fabric Warehouse SQL endpoint.
#
# Auth: acquires an Entra access token via the Azure CLI (reusing your existing
#       "az login" session) and connects with .NET SqlClient. This needs NO
#       extra tooling (no sqlcmd) and is fully non-interactive - works for both
#       interactive users and service principals.
# =============================================================================
. "$PSScriptRoot/common.ps1"
$cfg = Import-FabricEnv
$token = Get-FabricToken

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '../..')
$statePath = Join-Path $repoRoot '.state.json'
$state = Get-Content $statePath -Raw | ConvertFrom-Json
$workspaceId = $state.workspaceId
$warehouseId = $state.warehouseId
if (-not $warehouseId) { throw 'warehouseId missing. Run 05-deploy-items.ps1 first.' }

Write-Step 'Resolving Warehouse SQL connection string'
$wh = Invoke-FabricApi -Method Get -Path "/workspaces/$workspaceId/warehouses/$warehouseId" -Token $token
$server = $wh.properties.connectionString
$database = $cfg.WAREHOUSE_NAME
if (-not $server) { throw 'Could not read Warehouse connectionString. The warehouse may still be provisioning.' }
Write-Ok "SQL endpoint: $server / DB: $database"

# Acquire a SQL access token (audience: Azure SQL / database.windows.net).
$sqlToken = Get-AccessToken -Resource 'https://database.windows.net/'

# Helper: run a .sql file, splitting it into batches on lines containing only GO.
function Invoke-SqlFile {
    param([string] $Path)

    $sql = Get-Content $Path -Raw
    $batches = [regex]::Split($sql, '(?im)^\s*GO\s*$') | Where-Object { $_.Trim() -ne '' }

    $conn = New-Object System.Data.SqlClient.SqlConnection
    $conn.ConnectionString = "Server=$server;Database=$database;Encrypt=True;TrustServerCertificate=False;Connect Timeout=60;"
    $conn.AccessToken = $sqlToken
    $conn.Open()
    try {
        foreach ($batch in $batches) {
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = $batch
            $cmd.CommandTimeout = 120
            [void] $cmd.ExecuteNonQuery()
        }
    } finally {
        $conn.Close()
    }
}

$sqlFiles = @(
    'fabric-items/sql/01-create-schema.sql',
    'fabric-items/sql/02-create-tables.sql',
    'fabric-items/sql/03-stored-procedures.sql'
)

foreach ($rel in $sqlFiles) {
    Write-Step "Executing $rel"
    Invoke-SqlFile -Path (Join-Path $repoRoot $rel)
    Write-Ok "$rel applied."
}

Write-Host 'Schema, tables and stored procedures deployed to the Warehouse.' -ForegroundColor Green
Write-Host 'Tip: run EXEC sales.usp_seed_orders; then EXEC sales.usp_refresh_orders_summary; to populate demo data.' -ForegroundColor DarkGray
