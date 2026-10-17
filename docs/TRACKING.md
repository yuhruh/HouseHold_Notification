# Tracking

Status legend: ☐ todo · ◐ in progress · ☑ done · ⏸ blocked (needs Alex)

## M0: Foundations + push spike

| Task | Status | Notes |
|---|---|---|
| git init, PRD in `docs/PRD.md` | ☑ | first commit |
| `rails new web` (Rails 8.1, Postgres, Tailwind, no Kamal) | ☑ | |
| Solid Queue/Cache/Cable on the single Postgres | ☑ | `db/migrate/*_create_solid_*`; verify a job runs on Railway |
| Docker entrypoint: chown Railway Volume, drop to uid 1000 | ☑ | verify on Railway |
| CI at repo root (`working-directory: web`) | ☑ | green on main |
| Sentry initializer (`SENTRY_DSN`) | ◐ | ⏸ needs Sentry project DSN |
| Gmail API delivery method + `bin/rails gmail:authorize` | ◐ | ⏸ needs sender Gmail + GCP project ("In production") |
| PWA manifest + service worker (push + receipt) | ☑ | |
| Push spike `/spike/push`, checks `/spike/checks` | ☑ | basic auth via `SPIKE_USER`/`SPIKE_PASSWORD` |
| VAPID keys in credentials | ☑ | never rotate casually |
| Railway service + Postgres + Volume + env vars, permanent URL | ☑ | project `household-tracker`, https://web-production-143a5.up.railway.app; runs as uid 1000; Solid Queue started in Puma |
| Volume survives a redeploy | ☑ | line written by deployment 824c80aa still present after redeploy 6c0e873a |
| GitHub repo (private) + CI | ☑ | `<owner>/HouseHold_Notification`; CI green on main (run 39069086790) |
| Push spike on a real Android phone → ADR 0003 | ⏸ | |
| Import dry-run #1 on the real CSV | ⏸ | needs the CSV export with the ID column |

Exit criteria: app live on Railway; volume file survives a redeploy; CI green; push received with
the app closed/screen off (ADR 0003); Gmail API test email arrives; Sentry receives the test
exception; dry-run #1 report logged below.

## Sheet cleanup log

| Round | Date | Errors | Warnings | Fixed | Time spent | Notes |
|---|---|---|---|---|---|---|
| 1 | | | | | | `bin/rails import:dry_run CSV=…` |
