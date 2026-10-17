# ADR 0001: Rails 8 + PostgreSQL on Railway

- Status: Accepted (2026-10)
- Context: Household tracker for a few family members; owner already runs a Railway project.
- Decision: Ruby on Rails 8.1 (Hotwire, importmap, Tailwind) with one Railway Postgres. Solid Queue
  runs inside Puma (`SOLID_QUEUE_IN_PUMA=1`); Solid Queue/Cache/Cable tables live in the primary
  database (Railway provides one), via regular migrations (`db/migrate/*_create_solid_*`).
- Consequences: ~$4–8/month extra on Railway Hobby; one web replica (also required by the Volume);
  no Redis; no separate worker service.
- Alternatives considered: Expo + Supabase (cheapest, but a second vendor and a TS stack), Rails +
  Supabase DB (saves ~$2/month, adds a vendor), Expo app + Rails API (most code).
