# ADR 0003: Web Push reliability spike (M0)

- Status: **In progress**: the owner's Pixel 9 passed (tests 1–5, overnight retest 2026-10-20); family phones pending
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
| 4 | Pixel 9 / Android 17 / Chrome 155 | overnight, battery saver | 8 h (05:57) | 05:57:12 (201) | 07:49:27 | 112 min | ⚠ receipt late; notification time to confirm |
| 2b | Pixel 9 / Android 17 / Chrome 155 | screen off (~10 min idle) | 10 min (09:37, 10-19) | 09:37:12 (201) | 09:37:14 | 2.0 s | ✅ |
| 5 | Pixel 9 / Android 17 / Chrome 155 | overnight retest: unplugged, battery saver, Notification history on | 8 h (05:27, 10-20) | 05:27:09 (201) | 05:31:35 | 4.4 min | ✅ |

Email-link loop: open a link from Gmail on the phone → does it land signed in (Chrome cookie jar
shared with the installed PWA)? Result: _pending_ (meaningful once M1 sign-in exists; re-check then).

## Decision
_Pending._ If pushes are delayed/dropped beyond what email fallback covers, decide whether to pull
the v2 native Android shell forward.

Notes (2026-10-18): "Received" is when the service worker's receipt reached the server. Notification
permission first showed "denied" (blocked for the site in Chrome); allowing it in Chrome's site
settings fixed it. Extra "Send now" pushes at 22:57:43 and 23:10:48 arrived in 0.5 s and 1.1 s.

Notes (2026-10-19): test 4's push service accepted the push on time (05:57:12), but the receipt
only reached the server at 07:49:27. That looks like Android Doze holding the phone's network until
it woke, and the phone may have woken when it was picked up. Tests 2 and 4 both show the same
late-receipt pattern with the screen off. The open question is whether the notification itself
appeared on time (Chrome can show it while the receipt's network call waits) or also late.
Retest 2b (09:37) arrived in 2 s after ~10 min idle, so short idle is fine; the overnight retest
(10-19 night, Notification history on, unplugged) decides whether deep Doze delays notifications.

Notes (2026-10-20): overnight retest 5 was accepted at 05:27:09 and its receipt arrived at
05:31:35. The service worker posts the receipt only after showing the notification, so the
notification appeared by 05:31 at the latest, 4.4 min after sending, during deep Doze. The
notification text ("Scheduled 05:27 · sent 05:27:08") is written by the server at send time, not
the display time. A few minutes' delay is fine for a once-a-day digest, so the Pixel passes. Test
4's 112 min was not repeated. Left for X9: the family member's phone.
