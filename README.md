# Household Tracker

A shared, installable web app (PWA) for bills: expenses, maintenance and taxes, kept in shared
**ledgers** (帳本), one for a home, another for a company or anything else. It started as the
replacement for a family Google Sheet of household expenses, and reminds everyone before things are
due.

**Live:** https://household-tracker.up.railway.app

## Overview

The sheet held years of bills but had no reminders, no phone entry, no photos and no structure for
periods or payment methods. Household Tracker keeps the sheet's shape (✅/❌, Required vs Paid,
totals per type) and adds:

- one daily reminder digest per member, by Web Push, email and an in-app inbox;
- recurring bills that create themselves;
- a To Pay list, bill barcode scanning, receipt photos, Expense Analysis charts and a one-time
  import of the sheet history.

It runs as one Rails 8 service on Railway with one Postgres database, and supports zh-TW and English.
Desktop browsers and Android (installed PWA) are supported. iPhone is not a supported platform in v1
([ADR 0002](docs/adr/0002-pwa-over-native.md)), though the app opens in Safari and can be added to the
Home Screen.

## Features

**Bills**
- Expense, Maintenance and Tax records: category, title, details, billing period (year + start/end
  month, e.g. Jan. - Feb., Full Year), TWD or USD, amount due and paid, Payable From and due dates,
  paid date, payment method, notes and photos.
- One **Bills** page with two views switched at the top:
  - **To Pay**: overdue, due in the next 30 days, maintenance coming up, due later and no due date,
    most urgent first (side by side on a computer), with a count on the switch;
  - **All**: every record as one compact row, with search and filters (year, month, type, category,
    status including Outstanding, payment method) folded behind a **Filters** button. The filters in
    use show as removable tags.
- Derived status (unpaid, partly paid, paid, overdue) using each viewer's local date.
- **Record Payment** opens the form prefilled (paid in full, today, the usual payment method);
  maintenance reads as a task with **Mark Done**. Per-user **Remind Me Later**, and a history of every
  change.
- **Past Records** on a record opens the earlier periods of the same item (same category and details).
- The summary shows Paid per type and currency, and each amount links to the matching records.
- The list is paged: 10, 20 or 50 records per page, or a custom number (remembered on each device).
- **Export These N (CSV)** saves every record the filters match (not just the page shown);
  **Import CSV** sits next to it.
- On a computer the header stays at the top of every page, and so does the top of each view: the
  To Pay / All switch, and on All also the filters, summary, count and column headings, while the
  bills scroll under it. A phone scrolls the page as usual, under the pinned header.

**Scan a bill**
- New Record → **Scan the Bill's Barcodes** reads the three convenience-store barcodes on a Taiwan
  bill (三段式條碼) with the live camera or a photo: deadline and biller code, bill number, and amount.
  The form is filled with the amount, due date, year and category.
- Read on the phone: the browser's `BarcodeDetector` where it supports Code 39 (Android Chrome),
  otherwise ZXing, loaded only then (iPhone, Safari, Firefox). Nothing is uploaded until Save.
- Each ledger is asked once what a biller code means (category, and whether the barcode's deadline
  is the due date or 3 days after it, as on tax bills).
- Before filling, the records are checked: the same bill number means **Already in your records**, and
  a hand-entered record with the same category and period asks whether it's the same bill (saying yes
  stores the bill number on it).

**Recurring bills**
- Templates (e.g. water / electricity / gas every 2 months, the management fee yearly) generate
  the next unpaid bill ahead of time. Generation catches up after a missed run and never
  duplicates.
- Fixed amounts are filled in. For variable bills the last amount is shown as a hint.
- Changing a template previews every affected unpaid bill (before → after) and applies the changes
  in one transaction.

**Reminders**
- At most one digest per member a day, at their chosen hour (default 09:00): due soon, due today,
  overdue, Maintenance next-due, and repeating reminders for bills with no due date.
- Channels: Web Push (counted as delivered only when the device confirms it), email through the
  Gmail API, and the in-app inbox.
- The owner gets a daily summary of failed deliveries and can resend them from
  **Settings → Reminder delivery**.
- A red count on **Bills** (header and phone tab bar) shows the unpaid bills due today or earlier.

**Ledgers and accounts**
- Roles: owner, co-owner (edits records) and viewer (read-only). Members join by email invitation.
- Sign in with email + password (email confirmation required) or Google.
- A **ledger** (帳本; `Household` in the code) holds its own records, members, categories and
  settings, and is named by whoever creates it (a home, a company…). One account can belong to
  several ledgers.
- The **ledger menu** at the left of the header is named after the ledger you're in: switch ledgers,
  + New Ledger, Ledger Settings and Members.
- **Your menu** at the right: My Account, Theme (Light / Dark / Auto) and Language switches, Getting
  Started, Install App and Sign Out. On a phone both menus open as sheets from the bottom, and a tab bar
  holds Bills, Analysis and New Record.
- The **ledger home** has one **Bills** card (what's to pay: overdue, due in 30 days and the most
  urgent bills, beside the last 3 bills paid) and, under **Ledger Setup**, Recurring Bills,
  Categories and Payment Methods.
- **My Account**: profile photo, language, time zone (read-only until the pencil, then a dropdown
  grouped by region), reminder time and theme; change email; change the password, or for a
  Google-only account email a link to set one; connect or disconnect Google; leave a ledger;
  notification channels per ledger (Push, email); push devices; and the signed-in devices, folded,
  with **Sign Out All Other Devices**.
- The app updates itself; **Ledger Settings → App Version** shows **What's New** (from
  [`web/config/changelog.yml`](web/config/changelog.yml)).
- The activity log shows who did what.
- Account deletion in the app or from a public page, with ownership transfer.
- The owner can **delete all records** (re-authentication and the typed ledger name required),
  optionally keeping the recurring templates.
- English and Traditional Chinese for signed-in and signed-out visitors; the theme is remembered on
  each device.

**Photos**
- Added in two steps (choose, then upload). Downscaled in the browser, then rotated, stripped of all
  metadata (including GPS) and saved as JPEG on the server.
- Repeats are recognised by a perceptual fingerprint (dHash), both in the browser (tagged
  **Already added**) and on the server, which skips them.
- Served only to the ledger's members ([ADR 0004](docs/adr/0004-storage-volume.md)).

**Expense Analysis**
- Apache ECharts charts: monthly spend by type, the water / electricity / gas trend and billing
  cycles (timeline or against the same period last year), spend by category and by payment method,
  and a box plot of bill amounts.
- Filter by year (or all years), currency and type, and count spending **By Paid Date** or **By
  Billing Period**. Totals show what's paid, unpaid and overdue; each opens the records behind it.
- Clicking a chart element shows the records behind it.
- On a computer the title, filters, count-by switch and totals stay pinned under the header while
  the charts scroll.

**Sheet import**
- Upload the sheet's CSV export, review a preview of new / changed / unchanged / error rows, then
  commit.
- Re-importing the same sheet is harmless (it reports every row unchanged). Every import is kept
  in the import history.

## Scheduled jobs

Solid Queue runs inside Puma; the schedule is in [`web/config/recurring.yml`](web/config/recurring.yml).
Times are Asia/Taipei unless noted. Each heartbeat is a Healthchecks.io check outside Railway, so
it alerts even when the app is down.

| Job | When | What it does | Heartbeat |
|---|---|---|---|
| `SendRemindersJob` | Hourly at :05 | Sends each member's digest at their reminder hour, then queues the owner's failure summary | `REMINDER_HEARTBEAT_URL` (grace 3 h) |
| `OwnerFailureSummaryJob` | After each reminder run, once a day per ledger | One summary of failed deliveries for the owner | `DELIVERY_HEALTH_HEARTBEAT_URL` |
| `ConfirmPushReceiptsJob` | Hourly at :35 | Marks a push no device confirmed within 24 h as failed | — |
| `GenerateRecurringRecordsJob` | Daily 00:10 | Creates due bills from every template, in the owner's time zone | `GENERATE_HEARTBEAT_URL` (grace 26 h) |
| `Auth::CleanupJob` | Daily 03:30 | Removes unconfirmed sign-ups older than 7 days, expired sessions and Google handoffs | — |
| `DiskUsageJob` | Daily 03:45 | Checks the Railway volume and alerts (Sentry + `/fail`) at 80% use | `DISK_HEARTBEAT_URL` |
| `BackupJob` | Sundays 04:00 | `pg_dump` to the volume (last 4 kept), plus an encrypted copy emailed off Railway | `BACKUP_HEARTBEAT_URL` (grace 8 days) |
| `PhotoBackupReminderJob` | 1st of the month 09:00 | Reminds the owner to run `bin/download-photos` | — |
| `clear_solid_queue_finished_jobs` | Hourly at :12 | Clears finished Solid Queue jobs | — |

Errors from requests and jobs go to Sentry.

## Technical highlights

- **Rails 8.1 + Hotwire** (Turbo, Stimulus), importmap, Tailwind v4, Propshaft. No Node build
  except a small script that pins ECharts (`bin/build-echarts`).
- **One Postgres for everything:** Solid Queue, Solid Cache and Solid Cable share the primary
  database. There is no Redis.
- **Household-scoped tenancy:** every page lives under `/h/:household_id/…`. The
  `HouseholdScoped` concern resolves the membership and Pundit policies authorize each action.
- **The user's time zone is the only time zone:** it is detected from the browser at sign-up, and
  every "today", overdue check and reminder hour uses the zone of the person it's for. The
  database stores UTC.
- **Reliable reminder delivery:** claim → dispatch → settle, with unique indexes as locks, so a
  double run never sends twice. Push counts as delivered only after the service worker posts a
  receipt. Failures are surfaced to the owner, never re-sent in a flood.
- **Email without a mail provider:** a custom Action Mailer delivery method calls the Gmail API
  from a dedicated household Gmail account (`lib/delivery_methods/gmail_api.rb`).
- **No external object storage:** photos live on a Railway Volume through the Active Storage Disk
  service, and are sanitized before they are saved.
- **Backups you can restore:** weekly encrypted `pg_dump` (AES-256, PBKDF2) emailed off Railway,
  monthly photo downloads, and a `backup:restore_drill` task that restores into a scratch database
  and checks every photo file's size and checksum.
- **Bilingual:** zh-TW and English throughout (rails-i18n). Locale order: the user's setting →
  the language cookie → the browser's Accept-Language → zh-TW.
- **Bill barcodes on the device:** Code 39 is read in the browser (`BarcodeDetector`, or a vendored
  ZXing build in `public/vendor/`); the server (`Records::BillBarcode`) is the authority on what the
  three barcodes mean.
- **CI** (GitHub Actions, [`.github/workflows/ci.yml`](.github/workflows/ci.yml)): Brakeman,
  bundler-audit, importmap audit, RuboCop, unit/integration tests and system tests. Railway
  deploys `main` automatically.

## Getting started

Requirements: Ruby 3.4.11, PostgreSQL, and libvips (for photo processing). The app lives in `web/`.

```sh
cd web
bin/setup          # installs gems, prepares the database, starts the dev server
bin/dev            # later runs: Rails server + Tailwind watcher on http://localhost:3000
```

In development, email opens in the browser (letter_opener) and heartbeats are no-ops. Google
sign-in, Gmail sending and Web Push need the keys in Rails credentials; see
[docs/M0-SETUP.md](docs/M0-SETUP.md).

**Tests**

```sh
bin/rails test           # unit, controller and integration tests
bin/rails test:system    # browser tests (headless Chrome)
bin/ci                   # RuboCop, security scans and tests (CI also runs the system tests)
```

**Useful tasks**

```sh
bin/rails import:dry_run CSV=sheet.csv          # validate a sheet export without saving anything
bin/rails gmail:authorize                       # one-time OAuth for the Gmail sender account
bin/rails backup:decrypt IN=household-….dump.enc
bin/rails backup:restore_drill IN=household-….dump.enc PHOTOS=household-photos-….tgz
bin/download-photos                             # tar of the photos on the Railway volume (needs the Railway CLI)
```

**Deploy:** push to `main`. Railway builds the Dockerfile, runs migrations and restarts. Railway
setup, environment variables and the manual deploy steps are in [docs/M0-SETUP.md](docs/M0-SETUP.md).

## How to use

The full step-by-step guide, in both languages, is in the app at **Getting Started** (`/guide`).
In short:

1. **Sign up** with email or Google, and create your ledger (or accept an invitation).
2. **Invite people** from the ledger menu → **Members**: choose co-owner or viewer. They get an email with a link.
3. **Set up the lists** from the ledger's page: categories, payment methods and recurring
   templates. Or **Import CSV** on **Bills › All** with the sheet's CSV export.
4. **Install the app:** open your menu (your initial, top right) → **Install App** (or Chrome ⋮ →
   Install app on Android).
5. **Turn on notifications:** your menu → **My Account**, tick **Push** and tap **Enable
   notifications**. Choose your reminder time there too. On Android, set Chrome's battery use to
   Unrestricted so pushes arrive on time.
6. **Add bills:** **New Record**, and **Scan the Bill's Barcodes** to fill it from a paper bill.
7. **Every day:** check **Bills › To Pay**, tap **Record Payment** after paying, and **Add photos**
   for receipts. **Expense Analysis** shows where the money goes.
8. **If a reminder fails**, the owner sees it in the daily summary and can resend it from the
   ledger menu → **Ledger Settings → Reminder delivery**.

## Documentation

| Document | What's in it |
|---|---|
| [docs/PRD.md](docs/PRD.md) | Product requirements, business rules, architecture, data model and milestones |
| [docs/TRACKING.md](docs/TRACKING.md) | Milestone progress (M0–M7), exit checks and pending decisions |
| [docs/M0-SETUP.md](docs/M0-SETUP.md) | Railway, Sentry, Gmail API, Google sign-in, backups and the restore drill |
| [docs/NOTIFICATIONS.md](docs/NOTIFICATIONS.md) | Reminder channels, failure handling, getting push to arrive on phones, operator notes |
| [docs/adr/0001-rails-railway.md](docs/adr/0001-rails-railway.md) | Why Rails 8 + Postgres on Railway |
| [docs/adr/0002-pwa-over-native.md](docs/adr/0002-pwa-over-native.md) | Why a PWA instead of native apps |
| [docs/adr/0003-push-spike.md](docs/adr/0003-push-spike.md) | Web Push reliability tests on real Android phones |
| [docs/adr/0004-storage-volume.md](docs/adr/0004-storage-volume.md) | Photos on a Railway Volume, and the path to S3-compatible storage |
| [docs/adr/0005-m0-external-checks.md](docs/adr/0005-m0-external-checks.md) | Results of the outside-service checks X1–X10 |
| `/privacy` (in the app) | Privacy policy: what is stored, backups and deletion |
