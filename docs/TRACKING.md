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
| Gmail API delivery method + `bin/rails gmail:authorize` | ☑ | sender = the owner's personal Gmail (ADR 0005, X8); GCP project `household-mailer` In production; test email from production landed in the inbox 2026-10-18; family member's Gmail ✅ 2026-10-19 (the family member's invitation landed in his inbox, not spam) |
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
| Backups: weekly encrypted `BackupJob` + restore drill (before the real import) | ☑ | built 2026-10-19 (Sunday 04:00 Taipei, keep 4, encrypted email; `backup:decrypt`, `backup:restore_drill`). **Restore drill passed 2026-10-19 11:17** on the production backup emailed at ~11:15: decrypted with the passphrase from the password manager, restored into Postgres 18 (Docker), households 1 · users 1 · memberships 1 · categories 15 · records 0. Passphrase rotated 2026-10-19 12:01 (the drill-day one appeared in a screenshot); Railway and the password manager match by fingerprint. Monthly photo download comes with photos (M3) |
| CSV import preview → commit, re-import updates, undo, `record_events` | ☑ | 2026-10-19: upload → dry-run validation (failure page lists rows, nothing saved) → preview (new / update with three-way ⚠ conflicts / unchanged / deleted in app Skip-Re-create / new IDs paste-back / category mapping saved as aliases / maintenance chains Keep-Clear-New date / warnings / sheet Total vs Paid) → one-transaction commit with lock_version check → latest-batch undo. Real CSV trial (rolled back): 130 created, Paid 429,869 = Total, re-import 130 unchanged. Not yet: moving rows between chains, payment-method suggestion from Note, bulk reminder for unpaid rows |
| Real import into the family household | ☑ | Alex uploaded the 記錄 CSV into 我的家, 2026-10-19 (after backups + restore drill + passphrase rotation). **Production re-import check passed 2026-10-19 17:11:** same CSV → 0 new, 0 updated, 130 unchanged; still 130 records, Paid 429,869 (committed, so a 0-change batch is in the import history) |
| Categories editing UI | ☑ | 2026-10-19: add, rename (titles follow; old name saved as an alias), archive used / delete unused, remove import aliases |
| CSV export that round-trips | ☑ | 2026-10-19: Export CSV on the records list (current filters), 記錄 layout with the Total row; app-entered records export as `app-<record_no>` and re-import onto themselves. Real data: import → export → re-import = 130 unchanged |
| Undo refused after later edits / deletions (PRD M5) | ☑ | 2026-10-19 (photos join the check in M3) |
| M2 exit: family member invited and browsing the imported data | ☑ | 2026-10-19 17:16: Sam accepted the invitation and is a Co-owner of 我的家; no pending invitations left |

## M4: Recurring + reminders

| Task | Status | Notes |
|---|---|---|
| M4a: recurring templates + daily catch-up generation | ☑ | 2026-10-19: templates (interval, first month, months per bill, start date, due day + **due month offset** (our addition: due_day alone can't say "1月–2月 water is due in March"), lead days, fixed/variable amount, no-due-date reminder frequency); `GenerateRecurringRecordsJob` daily 00:10 Taipei in the owner's zone, links a single matching bill, asks when 2+ match; template changes confirm before updating untouched unpaid bills (amount; started period in place, not-started regenerated); delete keeps bills. Heartbeat via `GENERATE_HEARTBEAT_URL` (optional) |
| M4b: reminder engine (schedule, digests, email + in-app inbox, Upcoming, snooze, restart, maintenance Done, preferences) | ☑ | 2026-10-19: `Reminders::Schedule` (D−lead, D, D+3…D+30, final D+33; restart cycle; next-due; no-due-date frequencies), `SendRemindersJob` hourly at :05 (claim → delivery, one digest per member × household × channel × day + one same-day addition, catch-up sends only the latest stage, wording from today, stuck-pending recovery, `REMINDER_HEARTBEAT_URL`), `DeliverReminderJob` (3 retries; revoked Gmail token fails at once + heartbeat /fail), in-app inbox + 🔔, Upcoming page, personal snooze, restart after cap, maintenance Done, per-household channel toggles (viewers default off). Web Push channel joins in M5 |
| M4c: owner failure summary, delivery status page + resend, reminder heartbeats | ☑ | 2026-10-19: `OwnerFailureSummaryJob` after every reminder run, once per household per owner-local day (in-app always, email unless email failed), `DELIVERY_HEALTH_HEARTBEAT_URL`; Household settings → 提醒送達狀態 (owner only): failed digests, reasons, 3-in-a-row hint, Resend (10-min limit, drops paid items, resolves when nothing is left) and Resend all |
| M4 exit: Healthchecks.io checks created and URLs set in Railway | ☑ | 2026-10-19: project Household-Tracker, 4 checks (Reminder Job Ran 1h/3h, Delivery health 1d/2h, Recurring Generation 1d/26h, Backup 1w/8d), email integration on all 4; the four `*_HEARTBEAT_URL` variables set (names and URL format verified, values not viewed). Reminder Job Ran green from the 18:05 run. Alert path checked with the integration's Test (email arrived 18:00) instead of pausing the job 3h. Other checks turn green on their first run (00:10, next owner summary, Sunday 04:00) |

## M5: PWA + Web Push

| Task | Status | Notes |
|---|---|---|
| Push subscriptions, Enable notifications, Install app, Devices, lock-screen privacy | ☑ | 2026-10-19: `push_subscriptions` (upsert by endpoint, reassigned to the signed-in user; deleted on sign-out / sign-out-others / Remove / 404-410 / account deletion; kept, nullified, on session expiry); "Enable notifications" only from a tap; "安裝 App" via `beforeinstallprompt`; My account → 裝置 with Remove; `push_show_amounts` |
| Web Push channel: digests, device receipts, 24h failure, resend / send by email | ☑ | `Reminders::PushSender` (urgency high, TTL 24h, per-device `delivery_attempts`), `/push_receipts/:token` (single-use, rate-limited) marks `sent`; `ConfirmPushReceiptsJob` hourly fails unconfirmed pushes after 24h; owner summary also by push; 提醒送達狀態 shows per-device reasons, Resend, Send by email instead. `docs/NOTIFICATIONS.md` |
| Owner removes a member's device (PRD §14) | ☑ | 成員 page lists each member's devices for the owner, with Remove |
| M5 exit: push on installed Android PWA + desktop Chrome marks `sent`; phone off 24h → `failed`, owner notified, Resend delivers | ◐ | 2026-10-19: Pixel 9 ✅ (14:05 digest had no registered device → failed; after registering, Resend at 14:09:00 → receipt 14:09:01 → `sent`). Left: desktop Chrome, the 24h phone-off test, family phones (X9) |

## M3: Attachments

| Task | Status | Notes |
|---|---|---|
| Record photos + avatars, private serving, sanitize before attach, client downscale | ☑ | 2026-10-19: Active Storage Disk on the volume, `draw_routes = false`; `PhotosController` (members only; signed-out / non-member → 404; `Cache-Control: private, max-age=300`, `nosniff`, inline; 400px thumbnails); `Photos::Sanitizer` (autorotate, strip EXIF/GPS/XMP/ICC → sRGB, ≤2000px, JPEG q82, HEIC → JPEG); JPEG/PNG/WebP/HEIC, 10 MB, 10 per record; Stimulus canvas downscale; avatars (512 square, visible to shared households); household purge removes files; undo blocked by added photos; template changes keep bills with photos in place |
| Monthly photo backup | ☑ | `PhotoBackupReminderJob` (1st of the month 09:00 Taipei, only when photos exist) emails Alex to run `bin/download-photos` (tar over `railway ssh`; **untested from here**, since `railway ssh` was denied in this session) |
| M3 exit: upload from phone; survives a redeploy; non-member / signed-out → 404; no `/rails/active_storage` route | ☑ | 404s and the missing route are covered by tests. 2026-10-19: uploaded from the Pixel, redeployed (17:22, deployment 3f20cb3c), photo still there ✅. `bin/download-photos` ran after it: 192 KB archive, 3 valid JPEGs (photo, thumbnail, avatar), no GPS data |

## M6: Dashboard

| Task | Status | Notes |
|---|---|---|
| Charts, filters, drill-down | ☑ | 2026-10-19: `DashboardQuery` (spend pieces: paid-date month, or `Spend::Allocator` split by billing period; TWD/USD never mixed) feeds monthly-by-type bars, 水/電/瓦斯 lines (billing period by default, own toggle), category bars, payment-method pie, box plot (`Stats` = QUARTILE.INC, 5+ bills, outliers carry record_id → open the record), paid / unpaid / overdue cards; filters year, currency, type; mode remembered per browser; every chart has "view as table"; clicks load `/dashboard/drilldown` into a Turbo Frame from the same query |
| M6 exit: each clicked element's drill-down total equals the chart value | ☑ | tested for every point of every chart in both modes (`DashboardQueryTest`) |
| Dark-mode chart theme, ECharts zh-TW locale | ➖ | not needed for v1 (decided 2026-10-19): the app has no dark mode, and every chart label already comes from the app's own zh-TW/en strings. Not part of the M6 exit |

## M7: Release

| Task | Status | Notes |
|---|---|---|
| Privacy policy + `/account/deletion` page | ☑ | 2026-10-19: `/privacy` updated: self-service deletion link, what's collected (avatar, language/time zone, signed-in devices), the services the app runs on (Railway, Gmail, push service, Sentry), and backups: server copies expire within 4 weeks, off-server encrypted copies (email, computer) are deleted after 3 months (the owner's choice, 2026-10-19; the monthly photo-backup email reminds her). Same wording on `/account/deletion`. `/guide` is also in the header nav |
| Volume disk-usage alert | ☑ | 2026-10-19: `DiskUsageJob` daily 03:45 Taipei, `df` on `/rails/storage`, ≥80% → Sentry warning + `DISK_HEARTBEAT_URL` `/fail`. Optional for Alex: a 5th Healthchecks.io check (1 day / 2 h) and the variable |
| Repeat restore drill, now including photos | ◐ | 2026-10-19: `backup:restore_drill PHOTOS=…tgz` checks every restored blob's file (present, size, MD5). Left for Alex: Run backup now + `bin/download-photos` the same day, then the drill (docs/M0-SETUP.md §7) |
| Family onboarding guide (install + enable notifications) | ☑ | 2026-10-19: `/guide` (zh-TW / en by locale): accept invite, install, enable push, Chrome battery Unrestricted, what arrives daily, troubleshooting. Linked from the invitation email and My account → Notifications. Revisit the battery tip after the X9 overnight retest |
| Remove the M0 spike pages and jobs | ☐ | after X8 (2026-10-26: `Spike::GmailDurabilityJob`) and X9 (`/spike/push` on family phones) |
| M7 exit: family uses it for one billing cycle | ☐ | starts once M0 and M5 close |

## Pending decisions

### Payment methods from notes (proposed 2026-10-19, waiting for Alex)
**Problem:** the sheet has no payment-method column; how a bill was paid is free text in Note
("玉山ubear", "全支付(玉山unicard)", "中信轉帳"…). The import put it in `payment_note` and set no
`payment_method` (the PRD's "suggested payment method from Note" step was deferred), so the dashboard's
payment-method pie shows a single "(none)" slice and the records filter by payment method is empty.

**Proposal** (mock-up: `docs/mockups/payment-methods-from-notes.png`):
1. **付款方式 → 從備註指定付款方式** (owner / co-owner): lists each payment keyword found in notes with
   its record count and examples (from the real data: ubear ≈17, unicard ≈9, 玉山帳戶 6, 中信轉帳 5,
   大戶卡 4, 新光信用卡 2, 街口 2, Pi錢包 1). One choice per keyword, not per record, pre-filled with a
   suggestion: an existing payment method, "＋ new" (name + kind), or skip. A note matching two keywords
   uses the higher one (drag to reorder). Apply fills `payment_method` only on records that have none;
   notes are never changed. Expected: ≈45 records filled, ≈7 methods created, ≈85 notes untouched.
2. Every record stays editable (Edit → 付款方式).
3. **Imports** remember the keyword → method mappings and pre-fill them in the preview (changeable there).
4. **Recurring templates** already carry a payment method for the bills they generate.
5. **New records** start with the payment method of the household's last record in the same category.

**Open question:** for "全支付(玉山ubear)", count it under the **card** (ubear: "how much on each card",
recommended) or as a separate **全支付** method ("how much through each app")?

**Decision:** _pending (Alex)._

## Sheet cleanup log

| Round | Date | Errors | Warnings | Fixed | Time spent | Notes |
|---|---|---|---|---|---|---|
| 1 | 2026-10-18 | 26 rows (29 errors) | 4 | 0 | – | 132 rows, NOT READY. Errors: Paid > Required ×11; Paid without Finished Date ×10; blank Item + blank year ×2 rows (31–32); unrecognized month ×2 (49–50); 保險 missing 保單號碼/標的 ×2 (56, 74). Warnings: ✅ but underpaid ×2, complete but not ✅ ×1, maintenance chain without room ×1. Totals of clean rows: TWD Required 328,719 · Paid 324,016. Estimated fix: ~30–45 min in the sheet |
| 2 | 2026-10-18 | 4 rows (6 errors) | 4 | 22 rows | ~10 min | Left: IDs 26–27 empty placeholder rows; ID 44 month holds a date; ID 45 month blank. Warnings: complete but not ✅ ×2 (lines 6, 74), ✅ but underpaid ×2 (44, 59). Totals of clean rows: TWD Required 431,069 · Paid 426,366 |
| 3 | 2026-10-18 | 0 | 0 | 4 rows | ~30 min (several exports) | **READY.** 130 rows. Empty rows removed; month cells fixed (Sheets kept turning `10月` into dates: type `'10月`). Totals: TWD Required 433,569 · Paid 429,869 = sheet Total 429,869 ✓ (the sheet's Total sums Paid). ⚠ The ID column renumbers when rows are deleted (formula or refilled): before the M2 import it must be plain values that never change |
| 4 (dry-run #2) | 2026-10-19 | 0 | 0 | 0 | – | Same export as round 3, now also saved as Records with every import validation (rolled back): **READY**, Total 429,869 = Paid ✓. Re-run on the 10:25 export (after freezing the ID column): 130 rows, IDs 1–130, no gaps or repeats, 0 errors |
