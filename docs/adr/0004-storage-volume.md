# ADR 0004: Photos on a Railway Volume (Active Storage Disk)

- Status: Accepted (2026-10)
- Decision: Active Storage `Disk` service with root `/rails/storage`, backed by a Railway Volume on
  the web service. No R2/S3. Default Active Storage routes disabled (M3); photos served only via a
  membership-checked controller; sanitized synchronously before attach.
- Consequences: one replica; a few seconds of downtime per deploy; all backups stay inside Railway
  (accepted risk). The container starts as root only so `bin/docker-entrypoint` can chown the
  mount, then drops to uid 1000 with `setpriv`.
- Migration path: Active Storage `Mirror` service to an S3-compatible bucket if off-site copies or
  scaling become necessary.
