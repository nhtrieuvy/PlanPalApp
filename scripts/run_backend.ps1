param(
    [ValidateSet('local', 'production', 'test')]
    [string]$Environment = 'local',

    [ValidateSet('web', 'worker', 'beat', 'migrate', 'check', 'test')]
    [string]$Component = 'web',

    [string]$Bind = '0.0.0.0:8000'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $root 'planpalapp'
$python = Join-Path $root '.venv\Scripts\python.exe'

if (-not (Test-Path -LiteralPath $python)) {
    throw "Python virtual environment was not found at $python"
}
if ($Environment -eq 'local' -and -not (Test-Path -LiteralPath (Join-Path $backend '.env.local'))) {
    Write-Warning 'planpalapp/.env.local is missing. Copy .env.local.example and configure it once.'
}

$env:PLANPAL_ENV = $Environment
Push-Location $backend
try {
    switch ($Component) {
        'web' {
            & $python manage.py runserver $Bind
        }
        'worker' {
            & $python -m celery -A planpalapp worker -l info --pool=solo `
                -Q high_priority,default,plan_status,low_priority
        }
        'beat' {
            & $python -m celery -A planpalapp beat -l info
        }
        'migrate' {
            & $python manage.py migrate
        }
        'check' {
            & $python manage.py check
        }
        'test' {
            $env:PLANPAL_ENV = 'test'
            & $python manage.py test
        }
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Backend command failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
