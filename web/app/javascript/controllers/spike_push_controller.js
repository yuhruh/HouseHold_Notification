import { Controller } from "@hotwired/stimulus"

// M0 spike: registers the service worker and subscribes this browser to Web Push.
export default class extends Controller {
  static targets = ["status"]
  static values = { vapidPublicKey: String }

  async subscribe() {
    if (!("serviceWorker" in navigator) || !("PushManager" in window)) {
      return this.show("This browser doesn't support Web Push.")
    }
    const permission = await Notification.requestPermission()
    if (permission !== "granted") return this.show(`Permission: ${permission}`)

    const registration = await navigator.serviceWorker.register("/service-worker.js")
    await navigator.serviceWorker.ready
    const subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: this.urlBase64ToUint8Array(this.vapidPublicKeyValue)
    })

    const response = await fetch("/spike/push/subscription", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
      },
      body: JSON.stringify({ subscription: subscription.toJSON() })
    })
    this.show(response.ok ? "Subscribed ✓" : `Subscribe failed (${response.status})`)
  }

  show(message) {
    this.statusTarget.textContent = message
  }

  urlBase64ToUint8Array(base64String) {
    const padding = "=".repeat((4 - (base64String.length % 4)) % 4)
    const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/")
    return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0))
  }
}
