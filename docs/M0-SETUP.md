# M0 setup steps that need the owner's accounts

The code for M0 is in `web/`. These steps create or connect external accounts, so they are done by
Alex (or by Claude with the owner's go-ahead).

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

## 2. Sentry
Create a free Sentry project (platform: Rails), copy the DSN into `SENTRY_DSN`, then on
`/spike/checks` press **Raise a test exception** and confirm the alert email.

## 3. Gmail API sender
1. Create a dedicated Gmail account for the household (e.g. `…bills@gmail.com`).
2. Google Cloud Console: new project (separate from the future sign-in project) → enable
   **Gmail API** → OAuth consent screen (External) → **Publish app ("In production")**. In
   "Testing", refresh tokens expire after 7 days.
3. Credentials → OAuth client ID → **Desktop app**. Put client id/secret in credentials:
   `cd web && bin/rails credentials:edit`
   ```yaml
   gmail:
     client_id: ...
     client_secret: ...
     sender: household.bills@gmail.com
     refresh_token: (step 4)
   ```
4. `cd web && bin/rails gmail:authorize`, sign in as the sender, paste the code, then add the
   printed refresh token to credentials. Commit `config/credentials.yml.enc` (encrypted).
5. On `/spike/checks`, send a test email to a family Gmail address and confirm it's in the inbox.

## 4. Push spike (real Android phone)
Follow `/spike/push`, then fill in `docs/adr/0003-push-spike.md`.

## 5. Import dry-run #1
Add the `ID` column to the 記錄 tab (1…N, pasted as values), File → Download → CSV, then:
`cd web && bin/rails import:dry_run CSV=~/Downloads/記錄.csv` and log the result in
`docs/TRACKING.md` → Sheet cleanup log. The CSV contains household data: keep it out of git.

### Manual deploy
The `web` service is linked to `<owner>/HouseHold_Notification` with Root Directory `/web`, so a manual
upload must contain the whole repo. Run from `web/` (where the CLI link lives):

    railway up .. --path-as-root --ci

`railway up` alone from `web/` uploads only that folder, Railway then finds no `web/` inside it, falls
back to Railpack and the build fails. The URL is now **household-tracker.up.railway.app** (renamed
2026-10-18, before any users or OAuth clients); `APP_HOST` must always match it, or every page except
`/up` returns 403 (Rails host authorization).
