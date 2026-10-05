# Local and Production Environments

PlanPal uses one Django settings module and one Flutter application target.
Source files never need to be edited when switching environments.

## Environment selectors

| Layer | Selector | Values | Default |
|---|---|---|---|
| Django | `PLANPAL_ENV` | `local`, `test`, `production` | `local` |
| Flutter | `APP_ENV` build define | `local`, `production` | debug=`local`, release=`production` |

Django optionally loads `planpalapp/.env.<PLANPAL_ENV>`. Operating-system and
Fly environment variables always take precedence. The old `planpalapp/.env`
file remains a fallback so existing developer machines keep working.

Flutter accepts optional `API_BASE_URL` and `OAUTH_CLIENT_ID` build defines.
Use them for a physical device, staging URL, or rotated OAuth public client.
WebSocket URLs are derived automatically (`http -> ws`, `https -> wss`).

## First-time local setup

From the repository root in PowerShell:

```powershell
Copy-Item .\planpalapp\.env.local.example .\planpalapp\.env.local
notepad .\planpalapp\.env.local
```

Set the local MySQL password, OAuth client ID, and optional Cloudinary/Goong
credentials once. Do not commit `.env.local`.

Start MySQL, then start Redis if it is not already running:

```powershell
docker start planpal-redis
```

For the first Redis run:

```powershell
docker run -d --name planpal-redis -p 6379:6379 redis:7
```

If your existing Redis reports `Authentication required`, add its password to
`planpalapp/.env.local` once:

```env
LOCAL_REDIS_PASSWORD=your-local-redis-password
# LOCAL_REDIS_USERNAME=default   # only for an ACL username other than default
```

Do not place the password in `REDIS_URL` unless you intentionally want Celery,
cache, and Channels to share one Redis database. `LOCAL_REDIS_PASSWORD` keeps
the normal local split: Celery DB 0, cache DB 1, Channels DB 2.

Install and migrate:

```powershell
.\.venv\Scripts\python.exe -m pip install -r .\planpalapp\requirements.txt
.\scripts\run_backend.ps1 -Environment local -Component migrate
```

## Run locally

Use four terminals from the repository root:

```powershell
# Terminal 1: REST + WebSocket
.\scripts\run_backend.ps1 -Environment local -Component web

# Terminal 2: background jobs
.\scripts\run_backend.ps1 -Environment local -Component worker

# Terminal 3: exactly one scheduler
.\scripts\run_backend.ps1 -Environment local -Component beat

# Terminal 4: Android Studio emulator
.\scripts\run_flutter.ps1 -Environment local -Action run
```

The emulator default is `http://10.0.2.2:8000`. A physical phone must use the
computer's LAN address and both devices must be on the same network:

```powershell
.\scripts\run_flutter.ps1 -Environment local -Action run `
  -BaseUrl http://192.168.1.10:8000
```

Add that LAN IP to `ALLOWED_HOSTS` in `.env.local`. Allow TCP port 8000 through
Windows Firewall when testing from a physical phone.

Local checks and tests:

```powershell
.\scripts\run_backend.ps1 -Environment local -Component check
.\scripts\run_backend.ps1 -Environment test -Component test

cd .\planpal_flutter
flutter analyze
flutter test
```

The `test` profile always uses in-memory Celery, cache, and Channels backends,
so unit tests do not depend on Redis even if a developer `.env` enables it.

## Run the mobile app against production

No backend needs to run locally:

```powershell
.\scripts\run_flutter.ps1 -Environment production -Action run
```

Build the production APK:

```powershell
.\scripts\run_flutter.ps1 -Environment production -Action build-apk
```

Output: `planpal_flutter/build/app/outputs/flutter-apk/app-release.apk`.

For a temporary production-like or staging endpoint:

```powershell
.\scripts\run_flutter.ps1 -Environment production -Action run `
  -BaseUrl https://staging-api.example.com `
  -ClientId your-public-oauth-client-id
```

## Deploy backend production

`fly.toml` fixes `PLANPAL_ENV=production`; secrets remain outside Git. Configure
them once with Fly:

```powershell
fly secrets set `
  SECRET_KEY="a-long-random-secret" `
  DATABASE_URL="mysql://user:password@host:3306/planpal" `
  REDIS_URL="rediss://default:password@redis-host:6379/0" `
  CLIENT_ID="your-production-public-oauth-client-id" `
  CLOUDINARY_CLOUD_NAME="..." `
  CLOUDINARY_API_KEY="..." `
  CLOUDINARY_API_SECRET="..." `
  GOONG_API_KEY="..." `
  EMAIL_HOST_USER="..." `
  EMAIL_HOST_PASSWORD="..." `
  -a planpal-backend
```

Deploy and verify:

```powershell
fly deploy -a planpal-backend
fly status -a planpal-backend
fly logs -a planpal-backend
Invoke-WebRequest https://planpal-backend.fly.dev/health/live
Invoke-WebRequest https://planpal-backend.fly.dev/health/ready
```

The Fly release command runs migrations before Supervisor starts Daphne, one
Celery worker, and exactly one Celery Beat process on the same machine.

## Direct commands without scripts

The scripts are convenience wrappers. Equivalent selectors are:

```powershell
$env:PLANPAL_ENV='local'
.\.venv\Scripts\python.exe .\planpalapp\manage.py runserver 0.0.0.0:8000

cd .\planpal_flutter
flutter run --dart-define=APP_ENV=local
flutter build apk --release --dart-define=APP_ENV=production
```

## Safety behavior

- `PLANPAL_ENV=production` rejects `DEBUG=true`.
- Production refuses the development `SECRET_KEY` fallback.
- Production requires explicit `ALLOWED_HOSTS`.
- Production rejects `CORS_ALLOW_ALL_ORIGINS=true`.
- Production requires password-authenticated TLS Redis when
  `REQUIRE_EXTERNAL_REDIS=true`.
- Test commands force local in-memory infrastructure and cannot accidentally
  consume production Redis queues.
