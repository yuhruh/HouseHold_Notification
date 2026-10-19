# M0 setup steps that need the owner's accounts

The code for M0 is in `web/`. These steps create or connect external accounts, so they are done by
Alex (or by Claude with the owner's go-ahead). All of them were done on 2026-10-17/18; the notes
below record what actually worked.

## 1. Railway (done 2026-10-17 by Claude)
Project **household-tracker** (separate from Cat_Feeder_Tracker_V4): services `web` + `Postgres`,
volume `web-volume` at `/rails/storage`, URL **https://household-tracker.up.railway.app**
(permanent). The domain's target port is **80** (Thruster in front of Puma on 3000). Deployed with
`railway up` from `web/`; connect the GitHub repo for auto-deploys once it's pushed.
Spike basic auth: user `alex`, password in the `SPIKE_PASSWORD` Railway variable.

Original steps, for reference:
1. New service from this repo (or `railway up` from `web/`). **Root directory: `web`**. Builder:
   Dockerfile (`web/railway.json`).
2. Add a **PostgreSQL** database to the project; Railway injects `DATABASE_URL` into the service
   (reference variable `${{Postgres.DATABASE_URL}}`).
3. Add a **Volume** to the web service, mount path **`/rails/storage`**.
4. Generate a domain (Settings → Networking). This `*.up.railway.app` URL is **permanent**: PWA
   installs, push subscriptions and OAuth redirects are bound to it.
5. Variables:
   - `RAILS_MASTER_KEY` = contents of `web/config/master.key` (also store it in the password manager)
   - `APP_HOST` = the domain from step 4 (no `https://`)
   - `SOLID_QUEUE_IN_PUMA` = `1`
   - `SPIKE_USER`, `SPIKE_PASSWORD` = anything (protects `/spike/*`)
   - `SENTRY_DSN` = from step 2 below
6. Deploy, open `https://APP_HOST/spike/checks`.

## 2. Sentry (done 2026-10-18)
Project `household-tracker/household-tracker-web` (EU ingest); DSN in the Railway variable
`SENTRY_DSN`. The default "high priority issues" alert emails Alex; the test exception from
`/spike/checks` arrived as HOUSEHOLD-TRACKER-WEB-1. Gmail files Sentry mail under Updates: a filter
on `from:noreply@md.getsentry.com` → Categorize as Primary keeps alerts visible.

## 3. Gmail API sender (done 2026-10-18)
Sender: the owner's personal Gmail `owner@gmail.com` (decision and risks in ADR 0005, X8).
GCP project `household-mailer`. What worked, in order:
1. Google Auth Platform (console.cloud.google.com/auth) → Get started: External, app name, contacts.
2. Branding: **no logo** (a logo blocks publishing until Google verifies the app). Home page
   `https://household-tracker.up.railway.app` and privacy policy `…/privacy` are **required** to
   publish; authorized domain `household-tracker.up.railway.app`.
3. Data Access: leave empty (the authorize task requests `gmail.send` itself).
4. Audience → **Publish app** (In production). In Testing the refresh token dies after 7 days.
5. Clients → **Desktop app** (it accepts `http://localhost:<port>` redirects without registering them).
6. `cd web && EDITOR=nano bin/rails credentials:edit` → `gmail: client_id, client_secret, sender`.
7. `bin/rails gmail:authorize`, open the URL as the sender, Advanced → Go to … (unsafe) → Continue,
   paste the whole `http://localhost:1/?…` address back into the **terminal** (codes expire in
   minutes), then add the printed `refresh_token` to credentials. Never paste the token in chat.
8. Commit `config/credentials.yml.enc`, deploy, send a test from `/spike/checks`.
X8 runs `Spike::GmailDurabilityJob` (09:00/20:00 Taipei) to the Railway variable `X8_RECIPIENTS`
until 2026-10-26.

## 4. Google sign-in project (done 2026-10-18)
GCP project `household-signin`: same Branding rules (no logo; home page, privacy link and authorized
domain), Data Access `openid`, `userinfo.email`, `userinfo.profile` only, Published, **no test
users**. Client: **Web application** with redirect URIs
`https://household-tracker.up.railway.app/auth/google_oauth2/callback` and
`http://localhost:3000/auth/google_oauth2/callback`. Credentials: `google_sign_in: client_id,
client_secret`. Checked on `/spike/google`: X2 and X10 pass; X1 fails (Google ignores
`prompt=login`/`max_age=0` and never returns `auth_time`), so re-auth is an emailed code (ADR 0005).

## 5. Push spike (real Android phone)
Open `/spike/push` in **Chrome** (the installed app opens at `/`; use the "M0 checks" link on the
home page to reach the spike pages from it) and tap **Enable notifications**. If it says
"permission: denied": tap the icon left of the address bar → Permissions → Notifications → Allow,
and check Android Settings → Apps → Chrome (and 我的家) → Notifications. Run the four tests and fill
in `docs/adr/0003-push-spike.md`. "Received" is when the phone's receipt reached the server, which
can lag behind the notification itself when the screen is off.

## 6. Import dry-run
Export the 記錄 tab as CSV (keep it out of git), then
`cd web && bin/rails import:dry_run CSV=~/Downloads/<file>.csv`; log each round in
`docs/TRACKING.md` → Sheet cleanup log. Tips from rounds 1–3: Google Sheets turns `10月` into a date,
so type `'10月`; the **ID column must be plain values** (Copy → Paste special → Values only),
otherwise deleting a row renumbers every ID below it; the report checks the sheet's Total cell
against the Paid sum.

## 7. Backups (built 2026-10-19)
Railway Hobby can't create volume backups (X3). `BackupJob` runs every Sunday 04:00 Taipei: a
`pg_dump -Fc` to `/rails/storage/backups/` (keeps 4) and an encrypted copy
(`household-YYYY-MM-DD.dump.enc`, `openssl enc -aes-256-cbc -pbkdf2 -iter 600000`) emailed to Alex.
1. Railway → `web` → Variables: `BACKUP_PASSPHRASE` = the passphrase from the password manager.
   Optional: `BACKUP_RECIPIENT` (default: the Gmail sender), `BACKUP_HEARTBEAT_URL` (Healthchecks.io).
2. First run: `/spike/checks` → **Run backup now**; the email arrives in a minute or two.
3. Decrypt a copy: `cd web && bin/rails backup:decrypt IN=~/Downloads/household-….dump.enc`.
4. Restore drill (the dump is Postgres 18, so restore into an 18 server, e.g. Docker):

       docker run -d --rm --name drill-pg18 -e POSTGRES_PASSWORD=drill -p 55432:5432 postgres:18
       DRILL_DATABASE_URL=postgres://postgres:drill@localhost:55432/household_restore_drill \
         bin/rails backup:restore_drill IN=~/Downloads/household-….dump.enc
       docker stop drill-pg18

   It prints row counts per table and "Restore drill OK".

### Manual deploy
The `web` service is linked to `<owner>/HouseHold_Notification` with Root Directory `/web`, so a manual
upload must contain the whole repo. Run from `web/` (where the CLI link lives):

    railway up .. --path-as-root --ci

`railway up` alone from `web/` uploads only that folder, Railway then finds no `web/` inside it, falls
back to Railpack and the build fails. The URL is now **household-tracker.up.railway.app** (renamed
2026-10-18, before any users or OAuth clients); `APP_HOST` must always match it, or every page except
`/up` returns 403 (Rails host authorization).
