param(
    [ValidateSet('local', 'production')]
    [string]$Environment = 'local',

    [ValidateSet('run', 'run-web', 'build-apk', 'build-web')]
    [string]$Action = 'run',

    [ValidateSet('', 'debug', 'profile', 'release')]
    [string]$Mode = '',

    [string]$BaseUrl = '',
    [string]$ClientId = '',

    [string]$GoongMapTilesKey = '',
    [string]$FirebaseWebVapidKey = '',
    [string]$Device = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$frontend = Join-Path $root 'planpal_flutter'
$defines = @("--dart-define=APP_ENV=$Environment")

if (-not $GoongMapTilesKey) {
    $dotenvPath = Join-Path $frontend '.env'
    if (Test-Path -LiteralPath $dotenvPath) {
        $mapKeyLine = Get-Content -LiteralPath $dotenvPath |
            Where-Object { $_ -match '^GOONG_MAPTILES_KEY=' } |
            Select-Object -First 1
        if ($mapKeyLine) {
            $GoongMapTilesKey = ($mapKeyLine -split '=', 2)[1].Trim()
        }
    }
}

if (-not $FirebaseWebVapidKey) {
    $dotenvPath = Join-Path $frontend '.env'
    if (Test-Path -LiteralPath $dotenvPath) {
        $vapidKeyLine = Get-Content -LiteralPath $dotenvPath |
            Where-Object { $_ -match '^FIREBASE_WEB_VAPID_KEY=' } |
            Select-Object -First 1
        if ($vapidKeyLine) {
            $FirebaseWebVapidKey = ($vapidKeyLine -split '=', 2)[1].Trim()
        }
    }
}

if ($BaseUrl) {
    $defines += "--dart-define=API_BASE_URL=$BaseUrl"
}
if ($ClientId) {
    $defines += "--dart-define=OAUTH_CLIENT_ID=$ClientId"
}
if ($GoongMapTilesKey) {
    $defines += "--dart-define=GOONG_MAPTILES_KEY=$GoongMapTilesKey"
}
if ($FirebaseWebVapidKey) {
    $defines += "--dart-define=FIREBASE_WEB_VAPID_KEY=$FirebaseWebVapidKey"
}

Push-Location $frontend
try {
    $resolvedMode = $Mode
    if (-not $resolvedMode) {
        $resolvedMode = if ($Environment -eq 'production') { 'release' } else { 'debug' }
    }
    $modeFlag = "--$resolvedMode"

    if ($Action -eq 'build-apk') {
        & flutter build apk $modeFlag @defines
    }
    elseif ($Action -eq 'build-web') {
        # Keep CanvasKit and Flutter fonts on the same origin. This avoids a
        # production blank screen when a strict CSP or network blocks gstatic.
        & flutter build web $modeFlag --no-web-resources-cdn @defines
    }
    else {
        $arguments = @('run', $modeFlag) + $defines
        if ($Action -eq 'run-web') {
            $arguments += @('-d', 'chrome')
            if ($resolvedMode -eq 'debug') {
                Write-Warning 'Flutter Web debug mode is intentionally slower. Use -Mode profile for performance testing.'
            }
        }
        elseif ($Device) {
            $arguments += @('-d', $Device)
        }
        & flutter @arguments
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter command failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
