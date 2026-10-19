// Web Push: show the notification, then confirm receipt to the server so a delivery
// counts as "received by a device" (PRD §6 delivery status).
self.addEventListener("push", (event) => {
  const data = event.data ? event.data.json() : {}
  const title = data.title || "Household Tracker"
  const options = { body: data.body, data: { url: data.url || "/" } }

  event.waitUntil((async () => {
    await self.registration.showNotification(title, options)
    if (data.receipt_url) {
      try {
        await fetch(data.receipt_url, { method: "POST", keepalive: true, credentials: "omit" })
      } catch (_) {
        // Receipt is best effort; an unconfirmed delivery is reported after 24 h.
      }
    }
  })())
})

self.addEventListener("notificationclick", (event) => {
  event.notification.close()
  const path = event.notification.data.url
  event.waitUntil(
    clients.matchAll({ type: "window" }).then((clientList) => {
      for (const client of clientList) {
        if (new URL(client.url).pathname === path && "focus" in client) return client.focus()
      }
      if (clients.openWindow) return clients.openWindow(path)
    })
  )
})
