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
  end

  root to: redirect("/spike/checks")
end
