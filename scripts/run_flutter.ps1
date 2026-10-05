param(
    [ValidateSet('local', 'production')]
    [string]$Environment = 'local',

    [ValidateSet('run', 'build-apk')]
    [string]$Action = 'run',

    [string]$BaseUrl = '',
    [string]$ClientId = '',
    [string]$Device = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$frontend = Join-Path $root 'planpal_flutter'
$defines = @("--dart-define=APP_ENV=$Environment")

if ($BaseUrl) {
    $defines += "--dart-define=API_BASE_URL=$BaseUrl"
}
if ($ClientId) {
    $defines += "--dart-define=OAUTH_CLIENT_ID=$ClientId"
}

Push-Location $frontend
try {
    if ($Action -eq 'build-apk') {
        $mode = if ($Environment -eq 'production') { '--release' } else { '--debug' }
        & flutter build apk $mode @defines
    }
    else {
        $arguments = @('run') + $defines
        if ($Environment -eq 'production') {
            $arguments += '--release'
        }
        if ($Device) {
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
