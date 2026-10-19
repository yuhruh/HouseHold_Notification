# ADR 0005: M0 external checks (X1–X10)

- Status: In progress (2026-10). X1–X7 and X10 are settled; X8 is running; X9 waits on the family phones.
- Context: the PRD relies on behaviour of outside services and packages. Each check is verified for
  real in M0 and recorded here with its result and, when it fails, the fallback chosen (PRD →
  "M0 external checks").

| # | Check | Result | Decision |
|---|---|---|---|
| X1 | Google re-auth (`prompt=login`, `max_age=0`, `auth_time`) | ❌ → fallback | emailed 6-digit code; see below |
| X2 | `*.up.railway.app` as permanent URL in both GCP projects | ✅ | see below |
| X3 | Railway volume backups + restore into a scratch environment | ❌ → fallback | app-made backups, encrypted weekly email; see below |
| X4 | Image `pg_dump` major = Railway Postgres major | ❌ → fixed, ✅ | see below |
| X5 | HEIC decodes in the image | ✅ | see below |
| X6 | ECharts via importmap as one vendored file | ❌ → fallback, ✅ | see below |
| X7 | Volume writable without running the app as root | ✅ | `bin/docker-entrypoint` chowns, drops to uid 1000; file survived redeploy (TRACKING) |
| X8 | Gmail sender durable over 8 days | ◐ started 2026-10-18 | see below |
| X9 | Web Push on every family phone | ◐ Pixel 9 ✅ (overnight 2026-10-20); the family member's phone pending | ADR 0003 |
| X10 | Sign-in GCP project usable by non-test users | ✅ | see below |

## X4: `pg_dump` version (2026-10-18)
- Found: Railway runs `ghcr.io/railwayapp-templates/postgres-ssl:18` (server major 18). The image is
  `ruby:3.4.1-slim` on Debian 12 (bookworm), whose `postgresql-client` is **15.19**. `pg_dump`
  refuses to dump a newer server, so `BackupJob` would fail.
- Decision (the PRD fallback): the Dockerfile adds the PostgreSQL apt repo (PGDG) and installs
  `postgresql-client-$PG_MAJOR` with `ARG PG_MAJOR=18`. The rebuilt image has `pg_dump` **18.6**.
- Consequence: upgrading Railway Postgres to a new major means bumping `PG_MAJOR` in the same change.
  `BackupJob` still compares versions before dumping (PRD → Backups).

## X5: HEIC (2026-10-18)
- Found: on bookworm, `libheif1` 1.15.1 links `libde265-0` directly; there is no separate
  `libheif-plugin-libde265` package (the Dockerfile installs it only when it exists, i.e. on newer
  Debian). libvips 8.14.1 lists `.heic/.heif/.avif` loaders.
- Verified in the built amd64 image: `ImageProcessing::Vips` turns `test/fixtures/files/sample.heic`
  into a JPEG (`ff d8 ff`, 320×320) with no EXIF/XMP/ICC fields left (`strip: true`).
- Also found: `image_processing` 2.x (the Dependabot bump to 2.2.0) no longer depends on
  `ruby-vips`, so it had silently left the bundle. `ruby-vips` is now in the Gemfile.
- Decision: keep `image/heic` as an accepted type. M3 re-checks with the real sanitizer in CI and on
  Railway.

## X6: ECharts via importmap (2026-10-18)
- Found: `bin/importmap pin echarts` (ECharts 6.1.0 from jspm) vendors a 12 KB stub that imports
  hundreds of `./lib/...` modules plus a broken `zrender/lib/` pin, so the browser would fetch
  modules one by one. Fails the check.
- Decision (the PRD fallback): a **custom build**, made reproducibly with esbuild instead of the online
  builder. `vendor/echarts/entry.js` lists bar, line, pie, boxplot, scatter and the dataset,
  transform, grid, title, tooltip and legend components; `bin/build-echarts` bundles it into
  `vendor/javascript/echarts.js` (one file, no imports, 580 KB / 198 KB gzip), pinned as `echarts`.
- Verified: `/spike/charts` renders a bar chart and a box plot (with outliers) in headless Chrome; the
  only chart script is the digested `/assets/echarts-*.js`, nothing from a CDN.
- Consequence: adding a chart type or component means editing `entry.js` and re-running
  `bin/build-echarts` (needs Node locally; the app and CI don't).

## X8: Gmail sender (started 2026-10-18)
- Decision: the sender is **the owner's personal Gmail** (`owner@gmail.com`), not a dedicated
  household account as the PRD planned. Accepted risks: a leaked refresh token can send mail as Alex;
  every reminder shows in her Sent folder; an automated-sending lock would hit her main account.
  Switching later needs no code change: authorize a dedicated account with `bin/rails gmail:authorize`
  and update `gmail.sender`.
- Setup: GCP project `household-mailer`, Desktop OAuth client, consent screen **In production**
  (no logo, which would force brand verification; home page and `/privacy` links are required to
  publish). Account has 2-Step Verification and recovery options.
- Verified: a test email sent from production through the Gmail API landed in the inbox (2026-10-18).
- Log: 2026-10-19 09:00 run landed in the **Inbox** of both recipients; family.member shows
  mailed-by and signed-by gmail.com, TLS.
- Remaining: ~20 test mails to family inboxes over 8 days; on or after 2026-10-26 the refresh token
  must still work (proves it isn't on the 7-day Testing expiry) and nothing landed in spam.

## X2: Railway URL in both GCP projects (2026-10-18)
- `household-tracker.up.railway.app` was accepted as an authorized domain in both `household-mailer`
  and `household-signin`, both In production. Google accepted the redirect URIs
  `https://household-tracker.up.railway.app/auth/google_oauth2/callback` and the localhost one.
- Verified: on `/spike/google`, Sign in with Google returned to the app with a verified ID token for
  the owner's account.
- Lock-in (recorded as the PRD asks): installed PWAs, push subscriptions and OAuth redirects are bound
  to this host; moving off Railway later breaks all of them.

## X1: Google re-auth (2026-10-18)
- Test: signed in to Google, pressed Re-authenticate on `/spike/google` (request with `prompt=login`,
  `max_age=0` and a nonce). Google showed only the account chooser, **did not ask for the password**,
  and the verified ID token had **no `auth_time`**.
- Google's discovery document (`accounts.google.com/.well-known/openid-configuration`) confirms it:
  `claims_supported` has no `auth_time` and the `claims` request parameter isn't supported. Since
  `prompt=login` travels in a URL the user can edit, the server could never prove a fresh login anyway.
- Decision (the PRD fallback): Google-only users re-authenticate for sensitive actions with an
  **emailed 6-digit code** (10 min, single use, digest-stored, 5 attempts, send rate-limited). PRD
  §13, §15, S11, the data model (`reauth_codes`) and the account-deletion tests are updated.
- Consequence: sensitive actions for Google-only users depend on Gmail delivery (X8). Password users
  are unaffected (current password).

## X10: Sign-in project usable by non-test users (2026-10-18)
- `household-signin` consent screen In production, basic scopes only (`openid`, `email`,
  `profile`), no test users; IAM lists only the owner (`owner@gmail.com`).
- Verified: a second Google account with no role in the project and not a test user
  (`family.member@gmail.com`) signed in on `/spike/google` and got a verified ID token, with no
  "Access blocked" screen. A real family member's account is exercised again in M1.

## X3: Railway volume backups (2026-10-18)
- Found: the project is on the **Hobby** plan. The Postgres Backups tab says "Upgrade to Pro to create
  new backups, set up automated schedules, or enable point-in-time recovery". Railway's docs also say
  a backup restores only into the same project and environment (a new volume replaces the mounted
  one), so the "restore into a scratch environment" half could not pass on any plan.
- Decision (Alex, the PRD fallback): stay on Hobby. The weekly `BackupJob` (M2) writes a `pg_dump`
  to the volume (keep 4) **and emails it to Alex encrypted** (`openssl enc -aes-256-cbc -pbkdf2`,
  passphrase in credentials and the household password manager) through the Gmail sender: an
  off-Railway copy every week, which Pro's in-Railway backups would not give. Photos: monthly
  download (`bin/download-photos`). The M2 restore drill restores the decrypted dump into a scratch
  environment. PRD → Backups, M2 and the backup tests are updated.
- Accepted risks: photos since the last monthly download live only on the Railway volume; the backup
  email depends on the Gmail sender (X8); losing the passphrase makes every emailed copy unreadable.
