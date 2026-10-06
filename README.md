# PlanPal

![PlanPal brand](planpal_flutter/assets/brand/planpal-logo-light.svg)

**PlanPal is a collaborative travel planning platform that helps groups turn an idea into a coordinated trip.** Members can plan an itinerary together, make decisions, share updates and settle trip expenses in one place.

[Product website](https://planpal.app) · [Android releases](https://github.com/nhtrieuvy/PlanPalApp/releases) · [API documentation](https://planpal-backend.fly.dev/swagger/)

## What makes PlanPal useful

- **Plan together:** Create personal or group trips, arrange activities on a schedule, and see edits from collaborators in real time. Optimistic locking detects conflicting updates instead of silently overwriting them.
- **Make group decisions:** Collect availability before a trip exists; use polls, comments, mentions, reactions and pinned notes to coordinate; assign tasks and track checklist progress.
- **Keep trip finances clear:** Record who paid and who participated, split expenses equally, by percentage or by exact amount, review balances, and track settlement requests. Corrections are recorded as linked entries to preserve the expense history.
- **Stay connected on the go:** Chat in direct or group conversations, share places and consent-based live location, explore locations on Goong maps, and export schedules to ICS or Google Calendar.
- **Keep planning moving:** Save user-scoped drafts and queue supported changes while offline; sync them when connectivity returns. Search is limited to content the signed-in user can access.

## Product and engineering highlights

- One Flutter codebase supports responsive web and mobile experiences, with Vietnamese and English, light and dark themes, and web-specific navigation and layouts.
- The Django backend is organized into bounded contexts and uses service/repository boundaries to keep business rules out of views and UI widgets.
- REST APIs use the `/api/v1/` contract. Django Channels powers collaboration and chat; Celery with Redis handles background notifications, reminders and analytics aggregation.
- OAuth2 authentication, email OTP verification, role-based access checks, short-lived WebSocket tickets and user-scoped data protect collaborative features.
- CI checks Django configuration and migrations, runs backend tests, analyzes Flutter code, runs Flutter tests and builds the web release.
- The budget-conscious production setup runs the web service, one Celery worker and a single Celery Beat scheduler on one application machine, with managed MySQL and TLS-protected Redis.

## Technology

| Area | Technologies |
| --- | --- |
| Client | Flutter, Dart, Riverpod, GoRouter |
| Backend | Python, Django, Django REST Framework, Daphne |
| Realtime and jobs | Django Channels, WebSockets, Celery, Redis |
| Data and media | MySQL, Cloudinary |
| Maps and notifications | Goong, MapLibre, Firebase Cloud Messaging |
| Delivery | GitHub Actions, Docker, Fly.io, Cloudflare Workers |

## Run locally

See the environment guide for complete setup, local/test/production configuration and platform-specific commands:
[`docs/ENVIRONMENTS.md`](docs/ENVIRONMENTS.md).

Backend requirements: Python 3.11+, MySQL-compatible database and Redis 7+.
Frontend requirements: Flutter stable with Dart 3.8+.

```powershell
flutter pub get --directory planpal_flutter
.\scripts\run_flutter.ps1 -Environment local -Action run
```

For backend startup, migrations, Redis, Celery and deployment procedures, see [`docs/DEPLOYMENT_RUNBOOK.md`](docs/DEPLOYMENT_RUNBOOK.md).

## Project structure

```text
planpalapp/       Django API, domain contexts, workers and tests
planpal_flutter/  Flutter web/mobile client and tests
performance_tests/ Locust API and WebSocket load scenarios
docs/             Environment and deployment guides
```
