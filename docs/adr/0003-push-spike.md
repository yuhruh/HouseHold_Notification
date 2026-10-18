# ADR 0003: Web Push reliability spike (M0)

- Status: **In progress**: the owner's Pixel 9 tested 2026-10-18 (tests 1–3); overnight test and family phones pending
- Question: do Web Push reminders reliably reach an installed Android PWA with the app closed,
  the screen off, battery saver on, and overnight?
- Method: `/spike/push` (basic auth). Install the PWA, Enable notifications, queue pushes
  (now / 10 min / 1 h / 8 h). The service worker posts a receipt, so each send records when the
  push service accepted it and when the phone confirmed it.

## Results

| # | Phone / Android / Chrome | Condition | Queued | Accepted (HTTP) | Received | Latency | OK? |
|---|---|---|---|---|---|---|---|
| 1 | Pixel 9 / Android 17 / Chrome 155 | app open | now (21:50) | 21:50:26 (201) | 21:50:26 | 0.5 s | ✅ |
| 2 | Pixel 9 / Android 17 / Chrome 155 | app closed, screen off | 10 min (22:01) | 22:01:32 (201) | 22:27:08 | 25.6 min | ⚠ receipt late; notification time to confirm |
| 3 | Pixel 9 / Android 17 / Chrome 155 | battery saver on, screen off | 1 h (22:57) | 22:57:09 (201) | 22:57:11 | 1.4 s | ✅ |
| 4 | Pixel 9 / Android 17 / Chrome 155 | overnight, battery saver | 8 h (05:57) | | | | pending |

Email-link loop: open a link from Gmail on the phone → does it land signed in (Chrome cookie jar
shared with the installed PWA)? Result: _pending_ (meaningful once M1 sign-in exists; re-check then).

## Decision
_Pending._ If pushes are delayed/dropped beyond what email fallback covers, decide whether to pull
the v2 native Android shell forward.

Notes (2026-10-18): "Received" is when the service worker's receipt reached the server. Notification
permission first showed "denied" (blocked for the site in Chrome); allowing it in Chrome's site
settings fixed it. An extra "Send now" at 22:57:43 arrived in 0.5 s.
