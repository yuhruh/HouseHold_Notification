Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # PWA
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # M0 spike (basic auth; removed after M5)
  namespace :spike do
    get "push" => "push#show"
    post "push/subscription" => "push#subscribe"
    post "push/sends" => "push#create_send"
    post "push/receipts/:token" => "push_receipts#create", as: :push_receipt
    get "checks" => "checks#show"
    post "checks/volume" => "checks#write_volume", as: :write_volume
    post "checks/error" => "checks#raise_error", as: :raise_error
    post "checks/email" => "checks#send_email", as: :send_email
    get "charts" => "charts#show"
    get "google" => "google#show"
    post "google/start" => "google#start", as: :google_start
  end
  # Path registered as the OAuth redirect URI in the sign-in GCP project (omniauth's default in M1)
  get "auth/google_oauth2/callback" => "spike/google#callback"

  get "privacy" => "pages#privacy"
  root "pages#home"
end
