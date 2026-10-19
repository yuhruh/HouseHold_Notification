# Notifications

How Household Tracker reminds the family, what "delivered" means for each channel, and what to do
when reminders don't arrive. Product rules live in `docs/PRD.md` §6 and §16; this page is the
operator's and family's guide.

## Channels

| Channel | Turned on by | "Delivered" means | Fails when |
|---|---|---|---|
| In-app inbox (🔔) | always | written to the inbox | never |
| Email (Gmail API, sent from the household Gmail) | My account → 通知 → Email | Gmail accepted the message | Gmail rejects it (e.g. a revoked token `invalid_grant`, a bad address). Inbox arrival can't be confirmed: there are no read receipts or bounce processing in v1 |
| Web Push | My account → 通知 → 推播, **and** "Enable notifications" on each phone or computer | the device itself confirmed it showed the notification (the service worker posts a one-time receipt) | every device rejects it, no device has notifications enabled, or **no device confirms within 24 h** |

Owners and co-owners start with email and push on; viewers start with both off. Each member's
reminders arrive once a day at their reminder hour (default 08:00, in My account → Profile), as one
digest per household and channel. Lock-screen privacy: "Show bill names and amounts in
notifications" (My account → 通知) makes the push text generic when off.

## When a reminder isn't delivered

- The household owner gets **one summary a day** naming each member and channel that failed (in-app
  always; by push / email unless that channel is the one that failed).
- Household settings → **提醒送達狀態** (owner only) lists failed digests with the reason per device
  ("Pixel · Chrome: no confirmation in 24h", "subscription expired (410)", "no device has
  notifications enabled"), with **Resend**, **Resend all**, and **Send by email instead** for pushes.
  A member who failed 3 times in a row is highlighted.
- Resend only includes items that are still unpaid; if everything was paid meanwhile, the delivery
  is marked resolved.

## Phones: getting push to arrive

1. Open the app in **Chrome**, menu → **Install app** (or the "安裝 App" button in the header).
2. Open the installed app → My account → 通知 → **Enable notifications**, and allow.
3. If it says "blocked": tap the icon left of the address bar → Permissions → Notifications → Allow,
   and check Android Settings → Apps → Chrome (and the installed app) → Notifications.
4. Keep **email on as well**: Android may hold pushes while a phone sleeps (see ADR 0003).

Battery savers on some brands delay or drop pushes. Exempt **Chrome** (and the installed app):

- **Samsung:** Settings → Battery → Background usage limits → remove Chrome from "Sleeping apps" /
  "Deep sleeping apps"; Apps → Chrome → Battery → Unrestricted.
- **Xiaomi / Redmi / POCO:** Settings → Apps → Manage apps → Chrome → Battery saver → No
  restrictions; enable **Autostart**.
- **OPPO / realme / OnePlus:** Settings → Battery → App battery management → Chrome → allow
  background activity / Don't optimize; enable auto-launch.
- **vivo:** Settings → Battery → Background power consumption management → Chrome → allow.
- **Huawei / Honor:** Settings → Battery → App launch → Chrome → Manage manually, enable all three.
- **Pixel / stock Android:** Settings → Apps → Chrome → App battery usage → Unrestricted.

Then test: ask the owner to check 提醒送達狀態 the next morning, or send a reminder by giving a bill
a due date of today.

## Devices

My account → **裝置** lists every browser with push enabled, when it last confirmed a reminder, and
whether its session is signed in. Signing out on a browser removes its push subscription; a session
that merely **expires** keeps receiving reminders. **Remove** stops a lost or sold phone.

## Operator notes

- **Heartbeats (Healthchecks.io):** `REMINDER_HEARTBEAT_URL` (job ran; period 1 h, grace 3 h; `/fail`
  on a revoked Gmail token or an unexpected error), `DELIVERY_HEALTH_HEARTBEAT_URL` (daily owner
  summary; `/fail` when anything failed), `GENERATE_HEARTBEAT_URL` (daily recurring generation,
  grace 26 h), `BACKUP_HEARTBEAT_URL` (weekly backup, grace 8 days).
- **Gmail token revoked** (`invalid_grant`): re-run `bin/rails gmail:authorize` as the sender
  (docs/M0-SETUP.md §3), update credentials, deploy, then Resend all on 提醒送達狀態.
- **VAPID keys must never be rotated casually.** Every push subscription is bound to the VAPID
  public key in credentials (`vapid.public_key` / `vapid.private_key`). Rotating it silently breaks
  push on every device. Rotate only if the private key leaks; then announce it, expect every push to
  fail (404/410 or no confirmation), and ask the family to tap "Enable notifications" again on each
  device.
