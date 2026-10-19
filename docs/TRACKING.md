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
| Sentry initializer (`SENTRY_DSN`) | ☑ | project `household-tracker/household-tracker-web` (EU ingest); `SENTRY_DSN` set on Railway; test exception arrived as HOUSEHOLD-TRACKER-WEB-1; default "high priority issues" alert emails Alex |
| Gmail API delivery method + `bin/rails gmail:authorize` | ☑ | sender = the owner's personal Gmail (ADR 0005, X8); GCP project `household-mailer` In production; test email from production landed in the inbox 2026-10-18. Still to do: one to a family member's Gmail |
| PWA manifest + service worker (push + receipt) | ☑ | |
| Push spike `/spike/push`, checks `/spike/checks` | ☑ | basic auth via `SPIKE_USER`/`SPIKE_PASSWORD` |
| VAPID keys in credentials | ☑ | never rotate casually |
| Railway service + Postgres + Volume + env vars, permanent URL | ☑ | project `household-tracker`, https://household-tracker.up.railway.app; runs as uid 1000; Solid Queue started in Puma |
| Volume survives a redeploy | ☑ | line written by deployment 824c80aa still present after redeploy 6c0e873a |
| GitHub repo (private) + CI | ☑ | `<owner>/HouseHold_Notification`; CI green on main (run 39069086790) |
| Push spike on a real Android phone → ADR 0003 | ⏸ | |
| X4 `pg_dump` matches Railway Postgres | ☑ | was 15 vs 18; Dockerfile installs `postgresql-client-18` from PGDG (ADR 0005) |
| X5 HEIC decodes in the image | ☑ | HEIC fixture → stripped JPEG via `ImageProcessing::Vips`; `ruby-vips` re-added to Gemfile (ADR 0005) |
| X6 ECharts via importmap | ☑ | fallback: custom build, `bin/build-echarts` → one vendored file; `/spike/charts` (ADR 0005) |
| X8 Gmail sender durable over 8 days | ◐ | started 2026-10-18; ~20 test mails to family inboxes, token must still work on/after 2026-10-26 |
| X2 Railway URL as permanent OAuth host | ☑ | both GCP projects accept it; Google sign-in works on `/spike/google` (ADR 0005) |
| X1 Google forced re-auth | ☑ | failed (no password prompt, no `auth_time`); fallback adopted: emailed 6-digit code, PRD §13/§15 updated (ADR 0005) |
| X10 non-test user can sign in | ☑ | an account outside the project (not a test user, not in IAM) signed in on `/spike/google` (ADR 0005) |
| X3 Railway backups | ☑ | failed (Hobby plan can't create backups); fallback: weekly encrypted `pg_dump` emailed to Alex + monthly photo download, built in M2 (ADR 0005) |
| X9 push on every family phone | ⏸ | push spike on each phone (ADR 0003) |
| Import dry-run #1 on the real CSV | ☑ | round 1 logged below (26 rows with errors) |

Exit criteria: app live on Railway; volume file survives a redeploy; CI green; push received with
the app closed/screen off (ADR 0003); Gmail API test email arrives; Sentry receives the test
exception; dry-run #1 report logged below.

## M1: Auth, household, account lifecycle

M1 code complete 2026-10-19 (PRs #5–#7). Exit criterion "all auth/role/deletion tests pass": 129 tests green in CI.

| Task | Status | Notes |
|---|---|---|
| M1a: Rails 8 auth generator + confirmation (verified-only `email_address`), password reset, Google (`Auth::IdentityResolver`, `auth_handoffs`), 1-year sliding sessions, time zone + zh-TW/en, daily cleanup job | ☑ | PR #5, merged and deployed 2026-10-18; replaced `/spike/google` |
| M1b: households, roles, invitations, household-scoped routing + switcher, onboarding, Pundit | ☑ | PR #6, merged and deployed 2026-10-18. Default notification preferences on accept wait for M4/M5 (no table yet) |
| M1c: My Account, Household settings, ownership transfer, account/household deletion, emailed re-auth code | ☑ | PR #7, merged and deployed 2026-10-19. Avatar (M3), Devices / notification toggles / lock-screen privacy (M5) come with those milestones |

## M2: Records core + Sheet import

| Task | Status | Notes |
|---|---|---|
| First PR: `Record` / `Category` (+ `CategoryAlias`, `PaymentMethod`) models, default categories per household, import dry-run #2 (every `Record#valid?(:import)` + DB constraints in a rolled-back scratch household) | ☑ | committed to main 2026-10-19. Status rules + stored `settled`, `record_no` counter, Purge order updated. Real CSV (round 3 export): 130 rows, 0 errors |
| Records CRUD, filters, summary, mark-paid, payment methods UI | ☑ | 2026-10-19: list with year/month (period overlap), type, category, status, payment method and search; per-type and per-currency Required/Paid/Outstanding; record form (category sets the type, title defaults to it, end year from the year rule), optimistic locking; mark-paid (asks for the amount when Required is blank, date-only for Maintenance); `record_events` activity log (column `diff`, since `changes` is an Active Record method) with a snapshot on delete; payment methods add/edit/archive. Categories editing UI still to do |
| Backups: weekly encrypted `BackupJob` + restore drill (before the real import) | ☑ | built 2026-10-19 (Sunday 04:00 Taipei, keep 4, encrypted email; `backup:decrypt`, `backup:restore_drill`). **Restore drill passed 2026-10-19 11:17** on the production backup emailed at ~11:15: decrypted with the passphrase from the password manager, restored into Postgres 18 (Docker), households 1 · users 1 · memberships 1 · categories 15 · records 0. Passphrase to be rotated (it appeared in a screenshot). Monthly photo download comes with photos (M3) |
| CSV import preview → commit, re-import updates, undo, `record_events` | ☐ | |
| Real import into the family household | ☐ | gated on backups + frozen ID column |

## Sheet cleanup log

| Round | Date | Errors | Warnings | Fixed | Time spent | Notes |
|---|---|---|---|---|---|---|
| 1 | 2026-10-18 | 26 rows (29 errors) | 4 | 0 | – | 132 rows, NOT READY. Errors: Paid > Required ×11; Paid without Finished Date ×10; blank Item + blank year ×2 rows (31–32); unrecognized month ×2 (49–50); 保險 missing 保單號碼/標的 ×2 (56, 74). Warnings: ✅ but underpaid ×2, complete but not ✅ ×1, maintenance chain without room ×1. Totals of clean rows: TWD Required 328,719 · Paid 324,016. Estimated fix: ~30–45 min in the sheet |
| 2 | 2026-10-18 | 4 rows (6 errors) | 4 | 22 rows | ~10 min | Left: IDs 26–27 empty placeholder rows; ID 44 month holds a date; ID 45 month blank. Warnings: complete but not ✅ ×2 (lines 6, 74), ✅ but underpaid ×2 (44, 59). Totals of clean rows: TWD Required 431,069 · Paid 426,366 |
| 3 | 2026-10-18 | 0 | 0 | 4 rows | ~30 min (several exports) | **READY.** 130 rows. Empty rows removed; month cells fixed (Sheets kept turning `10月` into dates: type `'10月`). Totals: TWD Required 433,569 · Paid 429,869 = sheet Total 429,869 ✓ (the sheet's Total sums Paid). ⚠ The ID column renumbers when rows are deleted (formula or refilled): before the M2 import it must be plain values that never change |
| 4 (dry-run #2) | 2026-10-19 | 0 | 0 | 0 | – | Same export as round 3, now also saved as Records with every import validation (rolled back): **READY**, Total 429,869 = Paid ✓. Re-run on the 10:25 export (after freezing the ID column): 130 rows, IDs 1–130, no gaps or repeats, 0 errors |
