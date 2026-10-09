# PlanPal Web Compatibility

This checklist records the browser contract for the mobile-first Flutter client.
It complements `WEB_DEPLOYMENT.md`; it does not introduce separate web business
logic or API contracts.

## Feature matrix

| Feature | Web behavior | Requirement / fallback |
|---|---|---|
| Auth and email OTP | Same `/api/v1` repositories and validation | Production API must allow the deployed web origin through CORS |
| Group invite | Same invite-code, request and approval APIs | Auth redirect restores the requested route |
| Plan and activity | Same Riverpod providers and mutation APIs | Wizard content remains width-constrained |
| Polls, checklist and comments | Same collaboration repositories | Realtime refresh uses the authenticated group/plan sockets |
| Chat realtime | `wss://` plus a short-lived, single-use ticket | Browser URLs never contain the access token |
| Upload | `XFile` streaming multipart | Camera actions use the image file picker on web |
| Finance | Same expense, settlement and receipt endpoints | Receipt picker accepts JPG, PNG, WebP and PDF |
| Map and geolocation | Goong style through MapLibre Web | Geolocation requires HTTPS or localhost and browser permission |
| Audit log and analytics | Same paginated `/api/v1` endpoints | Analytics permissions remain server-enforced |
| ICS and calendar | Web Share/download fallback and external calendar links | Export filenames are sanitized for browser and desktop filesystems |
| Native share | Browser Web Share when available | `share_plus` provides its browser fallback when native sharing is unavailable |
| Push notification | FCM Web Push with explicit permission from Notification Settings | Requires HTTPS/localhost, the VAPID build define and `firebase-messaging-sw.js` |

## Browser acceptance pass

Test the latest stable Chrome and Edge at the compact, medium and expanded
breakpoints. Production geolocation, clipboard, share and service-worker checks
must run on HTTPS. `localhost` is acceptable for local development.

Run before deployment:

```powershell
flutter analyze
flutter test
flutter build web --release --dart-define=APP_ENV=production `
  --dart-define=GOONG_MAPTILES_KEY=<public-map-tiles-key> `
  --dart-define=FIREBASE_WEB_VAPID_KEY=<public-vapid-key>
```
