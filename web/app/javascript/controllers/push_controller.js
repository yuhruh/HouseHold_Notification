import { Controller } from "@hotwired/stimulus"

// "Enable notifications" (PRD §16): permission is asked only from a tap; the subscription is
// upserted on the server for the signed-in user.
export default class extends Controller {
  static targets = ["status", "enable", "disable"]
  static values = { vapidPublicKey: String, labels: Object }

  async connect() {
    if (!this.supported) return this.render("unsupported")
    const registration = await navigator.serviceWorker.register("/service-worker.js")
    const subscription = await registration.pushManager.getSubscription()
    this.render(Notification.permission === "denied" ? "denied" : subscription ? "enabled" : "disabled")
  }

  async enable() {
    const permission = await Notification.requestPermission()
    if (permission !== "granted") return this.render(permission === "denied" ? "denied" : "disabled")

    const registration = await navigator.serviceWorker.register("/service-worker.js")
    await navigator.serviceWorker.ready
    const subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: this.urlBase64ToUint8Array(this.vapidPublicKeyValue)
    })
    const response = await this.request("POST", "/push_subscriptions", { subscription: subscription.toJSON() })
    this.render(response.ok ? "enabled" : "failed")
    if (response.ok) window.location.reload()
  }

  async disable() {
    const registration = await navigator.serviceWorker.getRegistration()
    const subscription = await registration?.pushManager.getSubscription()
    if (subscription) {
      await this.request("DELETE", "/push_subscriptions/current", { endpoint: subscription.endpoint })
      await subscription.unsubscribe()
    }
    this.render("disabled")
    window.location.reload()
  }

  get supported() {
    return "serviceWorker" in navigator && "PushManager" in window && "Notification" in window
  }

  render(state) {
    this.statusTarget.textContent = this.labelsValue[state] || state
    if (this.hasEnableTarget) this.enableTarget.hidden = state !== "disabled"
    if (this.hasDisableTarget) this.disableTarget.hidden = state !== "enabled"
  }

  request(method, url, body) {
    return fetch(url, {
      method,
      headers: { "Content-Type": "application/json", Accept: "application/json",
                 "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content },
      body: JSON.stringify(body)
    })
  }

  urlBase64ToUint8Array(base64String) {
    const padding = "=".repeat((4 - (base64String.length % 4)) % 4)
    const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/")
    return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0))
  }
}
