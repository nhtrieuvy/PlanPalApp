# PlanPal Production Deployment Runbook

This runbook is the required path for production database and application
rollouts. The application API contract is unchanged by this process.

## Runtime topology

- One application machine: Supervisor starts Daphne ASGI, one Celery worker for
  all four PlanPal queues, and one Celery Beat scheduler.
- `Redis`: external managed Redis/Valkey with TLS and authentication.
- `MySQL`: external managed database with backups enabled.

Set the managed Redis URL as a Fly secret. Credentials must stay inside the URL
and must never be committed:

```powershell
fly secrets set REDIS_URL="rediss://default:PASSWORD@HOST:PORT/0" -a planpal-backend
```

After deployment, enforce one application machine:

```powershell
fly scale count 1 -a planpal-backend
```

Do not scale this topology above one machine: each machine starts Beat and would
duplicate scheduled work. Move Beat to an independent singleton process before
introducing horizontal application scaling.

## Pre-deployment checklist

1. Confirm CI backend and Flutter jobs are green.
2. Confirm `/health/live` and `/health/ready` return HTTP 200.
3. Confirm the managed Redis URL starts with `rediss://` and contains a password.
4. Confirm the database provider's automated backup is current.
5. Create an explicit pre-deploy backup for schema-changing releases.
6. Run `python manage.py makemigrations --check --dry-run`.
7. Review `python manage.py showmigrations --plan`.

For a local/self-managed MySQL backup, run:

```powershell
.\scripts\backup_mysql.ps1 -OutputDirectory .\backups
```

## Rollout

`fly deploy` runs `python manage.py migrate --noinput` in a one-off release
machine before replacing application machines. A failed migration fails the
release and leaves the previous application version serving traffic.

```powershell
fly deploy -a planpal-backend
fly scale count 1 -a planpal-backend
fly status -a planpal-backend
```

Validate after deployment:

```powershell
curl.exe https://planpal-backend.fly.dev/health/live
curl.exe https://planpal-backend.fly.dev/health/ready
fly logs -a planpal-backend
```

Confirm the single machine has started one `beat` scheduler and one worker that
consumes `high_priority`, `default`, `plan_status`, and `low_priority`.

## Rollback

Application rollback and database rollback are separate decisions. Prefer a
forward-compatible corrective migration. Never reverse a data migration until
its reverse behavior has been tested against a restored backup.

1. Stop the rollout if readiness fails.
2. Roll back the Fly release to the previous image.
3. Keep the new schema when it is backward-compatible.
4. Restore the database only for confirmed destructive corruption, using a
   separately verified backup and a documented maintenance window.
