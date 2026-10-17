# ADR 0002: PWA (desktop + Android) instead of native apps

- Status: Accepted (2026-10)
- Decision: v1 is a Rails PWA with Web Push. Desktop browsers and Android (installed PWA) only.
  No iPhone support in v1. A Hotwire Native Android shell is deferred to v2 and only built if the
  M0 push spike (ADR 0003) or real use shows Web Push is unreliable.
- Why: the native shell carried the largest security surface (PKCE handoff, App Links, cookie
  injection, FCM) for only the Android members; the PWA gives push with plain browser OAuth.
