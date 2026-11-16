# Household Tracker

A shared, installable web app (PWA) for bills: expenses, maintenance and taxes, kept in shared
**ledgers** (帳本), one for a home, another for a company or anything else. It started as the
replacement for a family Google Sheet of household expenses, and reminds everyone before things are
due. It also keeps track of household **supplies** (toilet paper, shampoo, drinks…) and says when to
buy more.

**Live:** https://household-tracker.up.railway.app

## Overview

The sheet held years of bills but had no reminders, no phone entry, no photos and no structure for
periods or payment methods. Household Tracker keeps the sheet's shape (✅/❌, Required vs Paid,
totals per type) and adds:

- one daily reminder digest per member, by Web Push, email and an in-app inbox;
- recurring bills that create themselves;
- utility bills that fill themselves in: gas (欣桃天然氣) from the company's site, electricity (台電)
  and water (台水) from their bill emails, each marked paid when the company says so;
- a To Pay list, bill barcode scanning, receipt photos, Expense Analysis charts, a weekly backup to
  the owner's Google Drive and a one-time import of the sheet history;
- **Supplies**: what the household keeps in stock, what it paid and where, a predicted run-out date
  for each item and a restock alert in time to buy more, with product barcodes and Taiwan e-invoice
  (發票) QR codes to fill things in.

It runs as one Rails 8 service on Railway with one Postgres database, and supports zh-TW and English.
Desktop browsers and Android (installed PWA) are supported. iPhone is not a supported platform in v1
([ADR 0002](docs/adr/0002-pwa-over-native.md)), though the app opens in Safari and can be added to the
Home Screen.

## Features

**Bills**
- Expense, Maintenance and Tax records: category, title, details, billing period (year + start/end
  month, e.g. Jan. - Feb., Full Year), TWD or USD, amount due and paid, Payable From and due dates,
  paid date, payment method, notes and photos.
- One **Bills** page with three tabs under the title, each with a count:
  - **To Pay**: only what needs doing now (overdue, due in the next 30 days, maintenance coming up
    and no due date), most urgent first, in two or three columns on a computer, with a **Next up**
    line for what comes after;
  - **Coming Up**: bills due after 30 days and recurring bills not created yet, by month, each
    saying when it moves to To Pay;
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
- A recurring bill's next period shows in To Pay or Coming Up before the daily job creates it, but
  not when an imported bill for the same period is waiting to be linked. Recurring maintenance
  without a due day gets one at the period start.

**Utility bills** (Ledger Settings, each with its own page)
- **Gas Account** (owner): one 欣桃天然氣 用戶編號 per ledger. Every working day at 11:30 the app
  checks 欣桃's paid and unpaid bills, adds new gas bills (amount, 限繳日) and marks matching bills
  paid. **Check Now** runs it at once.
- **Electricity (台電)** and **Water (台水)**: whoever receives the company's e-bill emails has Gmail
  forward them to the ledger's **forwarding address** (one per ledger, shared by both companies).
  The bill notice fills in or adds the bill with its amount and 繳費期限; the paid notice marks it
  paid. The first email sets the 電號 / 水號, and mail for any other number is ignored.
- The Electricity / Water page shows the status (Setting up, Waiting, Forwarding works), the latest
  bill and when the next email is expected, then the setup as 3 steps: the owner sends a setup
  email to each person who forwards (it has a **Copy address** link to a public page showing only
  the address), confirms Gmail's forwarding request with **Confirm Forwarding**, and the person adds
  the Gmail filter. A bill email forwarded by hand also works.
- In every case a bill already entered is matched by its period and filled in, never added twice;
  bills already paid are never changed and nothing is deleted. Every email read or ignored is listed
  under Recent activity, and the owner is told when a bill email is a week late.

**Reminders**
- At most one digest per member a day, at their chosen hour (default 09:00): due soon, due today,
  overdue, Maintenance next-due, and repeating reminders for bills with no due date.
- Channels: Web Push (counted as delivered only when the device confirms it), email through the
  Gmail API, and the in-app inbox.
- The owner gets a daily summary of failed deliveries and can resend them from
  **Settings → Reminder delivery**.
- **Bill paid**: when a utility bill is marked paid automatically, members with it on (owners and
  co-owners by default; **My Account → Notifications**) get an inbox item and a push, or an email
  when push is off or no device confirms it within an hour.
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
  Started, About This App, Install App and Sign Out. On a phone both menus open as sheets from the bottom, and a tab bar
  holds Bills, Analysis, Supplies and New (its **Add new** sheet closes on Cancel or a tap outside
  it). The header's **+ New ▾** menu adds a bill, a supply item or a purchase, or scans a barcode or
  receipt.
- The **ledger home** has one **Bills** card (what's to pay: overdue, due in 30 days, a count of
  what's coming up and the most urgent bills, beside the last 3 bills paid) and, under **Ledger Setup**, Recurring Bills,
  Categories and Payment Methods.
- **My Account**: profile photo, language, time zone (read-only until the pencil, then a dropdown
  grouped by region), reminder time and theme; change email; change the password, or for a
  Google-only account email a link to set one; connect or disconnect Google; leave a ledger;
  notification channels per ledger (Push, email); push devices; and the signed-in devices, folded,
  with **Sign Out All Other Devices**.
- **Ledger Settings** has a menu of its sections at the left on a computer (a list on a phone):
  General, Members, Reminder delivery, Recurring Bills, Categories, Payment Methods, Gas Account,
  Electricity, Water, Google Drive Backup, Activity and Danger zone. Owner-only sections are hidden
  from everyone else.
- The app updates itself and shows a card with the first change. **About This App** (your menu)
  has the version (major.minor.patch), **Check For Updates** and **What's New** (from
  [`web/config/changelog.yml`](web/config/changelog.yml)); it's marked **New** until you open it.
- The activity log shows who did what.
- Account deletion in the app or from a public page, with ownership transfer.
- The owner can **delete all records** (re-authentication and the typed ledger name required),
  optionally keeping the recurring templates.
- English and Traditional Chinese for signed-in and signed-out visitors; the theme is remembered on
  each device.

**Google Drive Backup**
- The owner connects their own Google Drive (the `drive.file` scope, so the app sees only files it
  created). Every Sunday around 04:30 a CSV of all bills (named like `Home bills_20261101.csv`) and
  every new bill photo, in one folder per year, are saved there. **Back Up Now** and **Open Folder**
  are on the page.
- An empty ledger that connects to a Drive holding an earlier backup can **restore** its bills and
  photos, or start fresh.
- Disconnecting stops the backups (files stay in Drive). It disconnects on ownership transfer, and
  revokes Google's access only when no other ledger uses that Google account.

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
- Clicking a chart element shows the records behind it: period, item with details, paid, paid date
  and payment method (cards on a phone). A bill split across periods shows its share.
- On a computer the title, filters, count-by switch and totals stay pinned under the header while
  the charts scroll.

**Supplies** (`/h/:id/supplies`)
- Each item has a name, kind (toiletries, cleaning, kitchen, food & drink, health, other), unit
  (piece, roll, bottle…) and a whole-number count. Purchases record the date, how many, the total
  price, the store and an optional expiry date. The price per unit is worked out from the total
  (NT$289 for 12 · NT$24.1/roll), never typed in.
- **Run-out forecast** (`Supplies::Forecast`): purchases and counts form a timeline of known stock,
  and the usage between them gives a rate per day (the last 120 days count). An optional guess ("one
  lasts about N days") counts as 14 days of evidence, so the first numbers aren't wild. From the rate
  the app estimates what's left today ("~2 rolls"), the run-out date and a **buy-by** date (run-out −
  days it takes to buy − 2 days, or 4 while there are fewer than 3 readings). With no guess and no
  readings an item says **Not enough data yet**.
- The page has four tabs, like Bills, each with a count:
  - **To Buy** (opens first) groups what to restock now into **Out Or Buy Now**, **Buy In The Next 7
    Days** and **Expiring**, each in its own colour (softer in dark mode), with a **Next up** line;
  - **Stocked** lists what's enough for now by the month it moves to To Buy, then **Not Enough Data
    Yet**;
  - **Favorites** lists the items anyone starred, the ones to restock soonest first (on a phone the
    tab is the star and its count). With more than one person starring, **Starred by** (Everyone,
    Me, each name) shows one person's stars;
  - **All** is every item: cards on a phone, a table on a computer (the **Left** column is the
    number alone over the stock bar), with the estimated monthly spend and, on a computer, a search
    box.

  To Buy, Stocked and Favorites show their groups and cards in one centred column at every width.
- **All's filters** are switches after a **Filter** label, on a phone too, and any number can be on
  at once: **Expiring** (shown only while something is expiring) and one chip per category in use.
  Several categories show the items in any of them, and Expiring keeps only the expiring ones among
  them. A chosen chip is blue with a ✕ and a second tap clears it; chips and the search keep each
  other. While the list is narrowed, **Showing 3 of 10** and **Clear all** take the monthly
  estimate's place.
- **Favorites**: the owner and each co-owner have their own star, in their own colour (the owner
  amber, then teal, violet, rose… in the order people joined), always with an initial so colour is
  never the only cue. The star button is yours: at the top right of an item's card, in front of its
  name in the All table, or **Favorite** beside Edit on its page. A small tag beside it (★ S) is
  someone else's star, and the item's page says **Also starred by** with names. An item is in
  Favorites while anyone has it starred and counts once however many stars it has; taking your own
  star off leaves the others. Everyone in the ledger sees the same stars; a viewer sees whose they
  are but can't star. Archived items can't be starred.
- Every stock bar shows its **Total** over its right end: the most there has been right after a
  restock, never less than the last count ("Total: 25 bottles" on the item's page, "Total: 25" in
  the lists).
- An item's page has the **Stock Forecast** card with **−1 Used one** (updates in place, with Undo)
  and **Restocked**, **Inventory:** to correct the count, **Where to buy** (each store's cheapest
  price per unit, and the total spent), **History** and **Price history**, folded. **Edit** (a
  dialog on a computer) changes the item's settings and corrects its last purchase; **Archive**
  hides it and stops its alerts. **‹ Back to Supplies** returns to the view the item was opened
  from: the same tab, filters and search (remembered per browser tab).
- **One item, several brands:** an item (say Shampoo) keeps one count, one usage rate and one
  restock alert for every brand bought as it. A purchase can carry a **Product or brand** (filled in
  by a scan, taken from a receipt line, or typed), which shows in History, Price history, Where to
  buy and the lists' Last bought, and which the All search finds. The brand is only a label for
  comparing prices; the app doesn't count each brand separately.
- **New item** can include **I already bought these** (date, how many, price, store, expiry), so an
  item bought a while ago has a usage rate from the first day. **Also add to Ledger** on any purchase
  creates a paid expense in the 日用品 category.
- **Add**: **+ New ▾** in the header (and **New** in the phone tab bar) is the one place to add:
  Scan product barcode, Add a receipt, Supply item, Log a purchase… and Bill / record. **Log a purchase** lists the
  Buy soon items first.
- **Scanning**, read in the browser (camera, a photo, a pasted screenshot or the typed number):
  - a **product barcode** (EAN-13/JAN, EAN-8, UPC) goes to the item it was saved with (the
    Restocked form, product filled in), or is looked up in Open Food / Beauty / Products Facts and,
    for Japanese codes, Yahoo! JAPAN Shopping. A code no database knows opens the New item form
    with a **Product not found** note, and the barcode is remembered once the item is saved. For
    another brand of something already tracked, the New item form offers **It's one of my items**:
    pick the item, and saving the purchase remembers the barcode for it. **Edit** lists an item's
    barcodes with **Remove**; a barcode on an archived item moves to the item it is bought as next.
  - **Add a receipt** takes a printed **Taiwan e-invoice** (both QR codes of 電子發票證明聯, shown as
    "1 of 2 QR codes read") or up to 10 **invoice PDFs** (發票明細 from a store's email or order page;
    a locked PDF asks for its password). **Review items** lists every item by invoice (quantity,
    unit price, subtotal) to match to an item, add as new or skip; choices are remembered per store,
    shipping and handling fees start skipped, and lines that match nothing are tagged **Not found**.
    An invoice can be excluded, or marked **Not a supplies store** so its next receipts start out.
    **Not included** lists duplicates, invoices added before, PDFs with no item list (their total can
    go to the Ledger) and PDFs that couldn't be read. Each invoice can become one Ledger expense.
    Japanese receipts (レシート) have no item QR code and aren't supported.
  - Only the barcode number, the QR text or the PDFs' text leaves the device (with a generic
    User-Agent for lookups); photos and PDF files aren't uploaded.
- **Alerts** (`SupplyAlertsJob`, 09:00 Taipei): one message per person listing what to buy (on the
  buy-by date, or when the count reaches "alert me when only N are left"), what's probably out, and
  what will expire before it's used (7 days ahead for food & drink and health, 30 for the rest). Each
  is sent once and resets after a purchase or a higher count. Owners and co-owners get them by
  default (**My Account → Notifications → Supplies low or expiring**): inbox and push, or email when
  push is off or no device confirms it within an hour.
- Everyone in the ledger can see Supplies; owners and co-owners add, edit, archive and star.

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
| `ConfirmPushReceiptsJob` | Hourly at :35 | Marks a push no device confirmed within 24 h as failed; emails a Bill paid or Supplies push not confirmed within 1 h | — |
| `GenerateRecurringRecordsJob` | Daily 00:10 | Creates due bills from every template, in the owner's time zone | `GENERATE_HEARTBEAT_URL` (grace 26 h) |
| `SyncGasAccountsJob` | Weekdays 11:30 | Checks each 欣桃 用戶編號, adds new gas bills and marks paid ones | — |
| `PollUtilityMailJob` | Every 5 min | Reads the app's Gmail: Gmail forwarding confirmations and forwarded 台電 / 台水 emails | — |
| `WarnMissingUtilityMailJob` | Daily 09:00 | Tells the owner once per bill when a 台電 / 台水 email is a week late | — |
| `SupplyAlertsJob` | Daily 09:00 | Supplies to buy, probably out or expiring: one inbox item + push per person (email fallback) | — |
| `NotifyBillsPaidJob` | After a utility sync marks bills paid | Bill paid inbox item + push (email fallback) | — |
| `Auth::CleanupJob` | Daily 03:30 | Removes unconfirmed sign-ups older than 7 days, expired sessions and Google handoffs | — |
| `DiskUsageJob` | Daily 03:45 | Checks the Railway volume and alerts (Sentry + `/fail`) at 80% use | `DISK_HEARTBEAT_URL` |
| `BackupJob` | Sundays 04:00 | `pg_dump` to the volume (last 4 kept), plus an encrypted copy emailed off Railway | `BACKUP_HEARTBEAT_URL` (grace 8 days) |
| `ScheduleDriveBackupsJob` | Sundays 04:30 | Queues each connected ledger's Google Drive backup | — |
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
  from a dedicated household Gmail account (`lib/delivery_methods/gmail_api.rb`). The same mailbox
  receives forwarded utility emails: each ledger's address is the mailbox plus `+h<id>-<token>`,
  and mail is routed by sender domain to `Utilities::Taipower` or `Utilities::TaiwanWater`, then
  `Utilities::BillSync`, which gas uses too (`records.external_ref` stops a synced bill being
  added twice).
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
- **Invoice PDFs on the device:** pdf.js (`public/vendor/pdfjs-4.10.38/`, with its CJK cmaps) pulls
  each PDF's text pieces and their positions in the browser; `Supplies::InvoicePdfParser` finds the
  invoice number, date, seller and total by pattern and label, and the items from the table under
  the 數量 / 金額 heading (wrapped names join the row they sit beside). `Supplies::ReceiptBatch`
  reviews and saves several invoices in one transaction.
- **Supplies scanning on the device:** product barcodes and e-invoice QR codes are read the same way
  (`BarcodeDetector` or ZXing, on the live camera or a still photo). `Supplies::EInvoiceParser`
  decodes the two QR codes (Big5, UTF-8 or Base64 item names); `Supplies::BarcodeLookup` checks the
  household's own barcodes, then a 30-day shared cache of public product facts, then the outside
  databases, each with a 3-second timeout that falls back to an empty form.
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
[docs/M0-SETUP.md](docs/M0-SETUP.md). Two features need more setup:

- **Reading 台電 / 台水 emails** needs the Gmail sender authorized with both `gmail.send` and
  `gmail.modify` (run `bin/rails gmail:authorize` again if it was set up for sending only).
- **Google Drive Backup** needs `GOOGLE_DRIVE_CLIENT_ID`, `GOOGLE_DRIVE_CLIENT_SECRET` (its own
  OAuth client, redirect `/google_drive/callback`) and `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` /
  `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` (the refresh token is stored encrypted;
  `bin/rails db:encryption:init` generates them).
- **Japanese product names** (Supplies barcodes starting 45 / 49) need a free Yahoo! JAPAN
  developer Client ID in credentials as `yahoo_japan: client_id:`. Without it those codes use only
  Open Food Facts and the rest.

**Tests**

```sh
bin/rails test           # unit, controller and integration tests
bin/rails test:system    # browser tests (headless Chrome)
bin/ci                   # RuboCop, security scans and tests (CI also runs the system tests)
```

**Useful tasks**

```sh
bin/rails import:dry_run CSV=sheet.csv          # validate a sheet export without saving anything
bin/rails gmail:authorize                       # one-time OAuth for the Gmail sender (send + read forwarded bills)
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
4. **Connect utilities** (optional), ledger menu → **Ledger Settings**: **Gas Account** with the
   欣桃 用戶編號, and **Electricity** / **Water** where the owner sends the setup email to whoever
   receives 台電's or 台水's e-bills. The owner can also connect **Google Drive Backup** there.
5. **Install the app:** open your menu (your initial, top right) → **Install App** (or Chrome ⋮ →
   Install app on Android).
6. **Turn on notifications:** your menu → **My Account**, tick **Push** and tap **Enable
   notifications**. Choose your reminder time there too. On Android, set Chrome's battery use to
   Unrestricted so pushes arrive on time.
7. **Add bills:** **New Record**, and **Scan the Bill's Barcodes** to fill it from a paper bill.
8. **Every day:** check **Bills › To Pay** (and **Coming Up** for later), tap **Record Payment** after paying, and **Add photos**
   for receipts. **Expense Analysis** shows where the money goes.
9. **Supplies:** **+ New ▾ → Supply item** (or scan its barcode), say how many you have, and fill in
   **I already bought these** if you know when. Tap **−1 Used one** now and then, or correct the
   count under **Inventory:**, and tap **Restocked** (or scan the 發票) after shopping. The app learns
   how fast each item goes and sends a restock alert in time. Star the things you buy again and
   again to find them under **Favorites**.
10. **If a reminder fails**, the owner sees it in the daily summary and can resend it from the
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
