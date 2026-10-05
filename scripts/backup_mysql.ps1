param(
    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory = ".\backups"
)

$requiredVariables = @('DB_HOST', 'DB_PORT', 'DB_NAME', 'DB_USER', 'DB_PASSWORD')
$missingVariables = $requiredVariables | Where-Object {
    [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_))
}
if ($missingVariables.Count -gt 0) {
    throw "Missing database environment variables: $($missingVariables -join ', ')"
}

$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outputFile = Join-Path $resolvedOutput "planpal-$timestamp.sql"

$env:MYSQL_PWD = $env:DB_PASSWORD
try {
    & mysqldump `
        --host=$env:DB_HOST `
        --port=$env:DB_PORT `
        --user=$env:DB_USER `
        --single-transaction `
        --routines `
        --triggers `
        --set-gtid-purged=OFF `
        --result-file=$outputFile `
        $env:DB_NAME
    if ($LASTEXITCODE -ne 0) {
        throw "mysqldump failed with exit code $LASTEXITCODE"
    }
} finally {
    Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue
}

$backup = Get-Item -LiteralPath $outputFile
if ($backup.Length -eq 0) {
    throw "Backup file is empty: $outputFile"
}

Write-Output "Backup created: $outputFile ($($backup.Length) bytes)"
