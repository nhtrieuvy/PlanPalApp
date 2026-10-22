param(
    [Parameter(Mandatory = $true)]
    [string]$DatabaseId,

    [string]$Email = $env:UPSTASH_API_EMAIL,
    [string]$ApiKey = $env:UPSTASH_API_KEY,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Email) -or [string]::IsNullOrWhiteSpace($ApiKey)) {
    throw 'Set UPSTASH_API_EMAIL and UPSTASH_API_KEY to a read-only Developer API credential.'
}

$credentials = [Convert]::ToBase64String(
    [Text.Encoding]::UTF8.GetBytes("${Email}:${ApiKey}")
)
$databasePath = [Uri]::EscapeDataString($DatabaseId)
$statsUrl = "https://api.upstash.com/v2/redis/stats/$databasePath"
$stats = Invoke-RestMethod -Uri $statsUrl -Method Get -TimeoutSec 20 `
    -Headers @{ Authorization = "Basic $credentials" }

function Get-LatestCommandSample {
    param([object]$Stats, [string]$Command)

    $series = @($Stats.command_counts | Where-Object {
        $_.metric_identifier -eq $Command
    })
    if ($series.Count -eq 0) { return $null }

    $points = @($series[0].data_points | Where-Object { $null -ne $_ })
    if ($points.Count -eq 0) { return $null }

    return $points | Sort-Object { [DateTimeOffset]$_.x } | Select-Object -Last 1
}

$brpop = Get-LatestCommandSample -Stats $stats -Command 'BRPOP'
$publish = Get-LatestCommandSample -Stats $stats -Command 'PUBLISH'
$snapshot = [pscustomobject]@{
    captured_at_utc = [DateTimeOffset]::UtcNow.ToString('o')
    database_id = $DatabaseId
    total_monthly_requests = $stats.total_monthly_requests
    brpop_sample_at = if ($brpop) { $brpop.x } else { $null }
    brpop_sample_count = if ($brpop) { $brpop.y } else { $null }
    publish_sample_at = if ($publish) { $publish.x } else { $null }
    publish_sample_count = if ($publish) { $publish.y } else { $null }
}

if ($OutputPath) {
    $parent = Split-Path -Parent $OutputPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $snapshot | Export-Csv -LiteralPath $OutputPath -NoTypeInformation `
        -Append:(Test-Path -LiteralPath $OutputPath) -Encoding UTF8
}

$snapshot
