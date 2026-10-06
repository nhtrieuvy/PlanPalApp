# PlanPal Web Deployment

PlanPal Web reuses the mobile REST contracts, Riverpod state and feature
screens. Cloudflare Workers serves only the compiled Flutter static assets;
the Django API and WebSocket server remain on Fly.io.

## Local development

Create `planpal_flutter/.env` from `.env.example` and set the public Goong
Map Tiles key and Firebase Web Push VAPID key. Then start Django on
`127.0.0.1:8000` and run:

```powershell
.\scripts\run_flutter.ps1 -Environment local -Action run-web
```

The web client defaults to `http://127.0.0.1:8000`. Android emulator builds
continue to use `http://10.0.2.2:8000`.

Browser push requires a secure context. It can be tested on `localhost`; use
HTTPS for any shared test environment. Users opt in from Notification
Settings, so the browser permission prompt is tied to an explicit action.

## Firebase Web Push

1. Open Firebase Console, select the PlanPal project, then open Cloud
   Messaging > Web configuration.
2. Create or reuse a Web Push certificate and copy its public VAPID key.
3. Put `FIREBASE_WEB_VAPID_KEY=<key>` in `planpal_flutter/.env` for local use.
4. Pass the same public key as a build-time Dart define in CI/production.

`web/firebase-messaging-sw.js` handles background messages. Firebase config
and the VAPID public key are public browser identifiers, not server secrets.
The Firebase service-account credential must remain only on the backend.

## Production build

```powershell
.\scripts\run_flutter.ps1 `
  -Environment production `
  -Action build-web `
  -BaseUrl "https://planpal-backend.fly.dev" `
  -ClientId "your_public_oauth_client_id" `
  -GoongMapTilesKey "your_public_map_tiles_key" `
  -FirebaseWebVapidKey "your_public_vapid_key"
```

The generated Flutter service worker caches only same-origin app-shell and
static build resources. The API is cross-origin on Fly.io and is never routed
through a Cloudflare Worker proxy, so authenticated API responses are not
stored in the PWA cache. The build script also passes
`--no-web-resources-cdn`, keeping CanvasKit and Flutter fonts on the Worker
origin so the production CSP does not depend on Google-hosted runtime assets.

## Deploy to Cloudflare Workers

The repository uses Workers Static Assets, configured by `wrangler.jsonc`.
Unknown routes fall back to `index.html`, preserving URLs such as
`/groups/<id>` and `/plans/<id>`.

```powershell
cd planpal_flutter
npm install
npm run deploy
```

On the first deploy, Wrangler asks you to sign in to Cloudflare. Attach the
production custom domain (for example `planpal.app`) to the `planpal-web`
Worker in the Cloudflare dashboard.

`web/_headers` applies the production CSP and security headers. It disables
caching for `index.html`, service workers and mutable bootstrap files, while
allowing longer caching for static assets. Update the Fly and Goong hostnames
there before deployment if either endpoint changes.

## Backend origin configuration

Set the exact public frontend origin on Fly. Do not include a trailing slash:

```powershell
fly secrets set FRONTEND_ORIGIN=https://planpal.app
```

`FRONTEND_ORIGIN` is appended to both `CORS_ALLOWED_ORIGINS` and
`CSRF_TRUSTED_ORIGINS`. Keep `CORS_ALLOW_ALL_ORIGINS=false` in production. If
you test through a temporary `workers.dev` URL, configure that exact origin;
do not use a wildcard.

## Realtime security

Browser clients call `POST /api/v1/auth/websocket-ticket/` over HTTPS before
opening each socket. The returned ticket is single-use and expires after 45
seconds by default. Native releases retain the existing bearer-token query
parameter during the migration window.

## Release checks

```powershell
cd planpal_flutter
flutter analyze
flutter test
npm run preview
```

Verify login redirect restoration, hard refresh on a detail URL, IndexedDB
draft recovery, logout cleanup, Goong tiles, `wss://` reconnect, notification
permission and background push before promoting the Worker route.
## Performance profiling

Do not evaluate Flutter Web performance in debug mode. Run a profile build
against the selected environment instead:

```powershell
.\scripts\run_flutter.ps1 -Environment local -Action run-web -Mode profile
```

Production builds default to release mode. `-Mode` can explicitly select
`debug`, `profile`, or `release` for both web and mobile verification.
