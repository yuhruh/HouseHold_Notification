# Notifications: reliability notes

- **Android battery savers** (Xiaomi/MIUI, OPPO/ColorOS, Samsung "sleeping apps", etc.) can delay or
  drop Web Push. Per phone: Settings → Apps → Chrome → Battery → *Unrestricted / Don't optimize*,
  and don't put Chrome in "sleeping apps". Keep **email** enabled as the fallback channel.
- **Web Push "received"** means the phone's service worker confirmed it (receipt POST). A push
  accepted by Google but never confirmed within 24 h counts as failed and is reported to the owner.
- **Email "sent"** means the Gmail API accepted the message; inbox delivery can't be confirmed.
- **VAPID keys must never be rotated casually.** Every subscription is bound to the public key;
  rotating it breaks push on every device until each member taps "Enable notifications" again.
  Rotate only if the private key leaks, announce it, and expect all subscriptions to fail.
- **Gmail sender:** changing the sender account's password revokes the refresh token; re-run
  `bin/rails gmail:authorize` and update credentials.
