# 0006: Google Drive backup

**Decision:** a ledger's owner can connect a Google account, and each Sunday (and on Back Up Now) the
app saves a CSV of every bill and any new photos to a folder in that account.

- **Scope:** `drive.file` only, a non-sensitive scope limited to files the app created. Asked for in
  its own consent step with its own OAuth client (`GOOGLE_DRIVE_CLIENT_ID`, `GOOGLE_DRIVE_CLIENT_SECRET`),
  so Google sign-in keeps its basic scopes and revoking Drive access doesn't touch sign-in.
- **Token:** the refresh token is the first secret stored per household, encrypted with Active Record
  Encryption (`ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`).
  Losing those keys means owners connect again. The feature stays hidden until all four are set.
- **Add-only:** nothing is deleted from Drive, so a bill deleted in the app stays backed up.
- **Ownership:** the connection belongs to the owner who made it and ends when ownership is transferred,
  so a former owner stops receiving the ledger's data.
- **Not a replacement** for the weekly encrypted database backup, which is what a restore uses.
