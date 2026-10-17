# ADR 0003: Web Push reliability spike (M0)

- Status: **Pending: results to be filled in after testing on a real Android phone**
- Question: do Web Push reminders reliably reach an installed Android PWA with the app closed,
  the screen off, battery saver on, and overnight?
- Method: `/spike/push` (basic auth). Install the PWA, Enable notifications, queue pushes
  (now / 10 min / 1 h / 8 h). The service worker posts a receipt, so each send records when the
  push service accepted it and when the phone confirmed it.

## Results

| # | Phone / Android / Chrome | Condition | Queued | Accepted (HTTP) | Received | Latency | OK? |
|---|---|---|---|---|---|---|---|
| 1 | | app open | now | | | | |
| 2 | | app closed, screen off | 10 min | | | | |
| 3 | | battery saver on | 1 h | | | | |
| 4 | | overnight | 8 h | | | | |

Email-link loop: open a link from Gmail on the phone → does it land signed in (Chrome cookie jar
shared with the installed PWA)? Result: _pending_ (meaningful once M1 sign-in exists; re-check then).

## Decision
_Pending._ If pushes are delayed/dropped beyond what email fallback covers, decide whether to pull
the v2 native Android shell forward.
