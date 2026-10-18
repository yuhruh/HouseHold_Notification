# ADR 0005: M0 external checks (X1–X10)

- Status: In progress (2026-10). X4, X5, X6 and X7 are settled; the rest wait on the owner's accounts and phones.
- Context: the PRD relies on behaviour of outside services and packages. Each check is verified for
  real in M0 and recorded here with its result and, when it fails, the fallback chosen (PRD →
  "M0 external checks").

| # | Check | Result | Decision |
|---|---|---|---|
| X1 | Google re-auth (`prompt=login`, `max_age=0`, `auth_time`) | ⏸ | needs the sign-in GCP project |
| X2 | `*.up.railway.app` as permanent URL in both GCP projects | ⏸ | needs both GCP projects |
| X3 | Railway volume backups + restore into a scratch environment | ⏸ | changes plan/production settings: needs the owner's go-ahead |
| X4 | Image `pg_dump` major = Railway Postgres major | ❌ → fixed, ✅ | see below |
| X5 | HEIC decodes in the image | ✅ | see below |
| X6 | ECharts via importmap as one vendored file | ❌ → fallback, ✅ | see below |
| X7 | Volume writable without running the app as root | ✅ | `bin/docker-entrypoint` chowns, drops to uid 1000; file survived redeploy (TRACKING) |
| X8 | Gmail sender durable over 8 days | ⏸ | needs the sender account |
| X9 | Web Push on every family phone | ⏸ | ADR 0003 |
| X10 | Sign-in GCP project usable by non-test users | ⏸ | needs the sign-in GCP project |

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
