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
fly deploy --ha=false -a planpal-backend
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

For 48 hours after deployment, compare Upstash's Usage > Top Commands Usage
(`BRPOP` and `PUBLISH`) and the database's monthly request quota at deployment,
24 hours, and 48 hours. Record the timestamps and deltas, not just the graph's
absolute values. With a single idle worker, expect roughly 180 `BRPOP` and 60
worker-heartbeat `PUBLISH` calls per hour; periodic jobs and user activity add
to this baseline. If the quota grows faster, inspect Upstash Monitor and Fly
logs before changing polling or heartbeat settings again. Operational `AUTH`
and `PING` commands appear in the usage graph but are not billed by Upstash.

To record comparable snapshots without copying chart values manually, create
an Upstash **read-only Developer API key** and set `UPSTASH_API_EMAIL` and
`UPSTASH_API_KEY` in the local shell (never in Git or Flutter build defines).
Find the database ID in Upstash Console, then run at deployment, +24 h, +48 h:

```powershell
.\scripts\check_upstash_usage.ps1 -DatabaseId 'YOUR_DATABASE_ID' `
  -OutputPath .\logs\upstash-usage.csv
```

The script reads the monthly quota counter and the latest `BRPOP`/`PUBLISH`
samples through Upstash's Developer API. A Redis URL alone cannot access these
account-level statistics. `logs/` is ignored by Git.

## Rollback

Application rollback and database rollback are separate decisions. Prefer a
forward-compatible corrective migration. Never reverse a data migration until
its reverse behavior has been tested against a restored backup.

1. Stop the rollout if readiness fails.
2. Roll back the Fly release to the previous image.
3. Keep the new schema when it is backward-compatible.
4. Restore the database only for confirmed destructive corruption, using a
   separately verified backup and a documented maintenance window.
