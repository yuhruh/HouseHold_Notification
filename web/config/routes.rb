Rails.application.routes.draw do
  # Auth (PRD §10)
  resource :session
  resources :passwords, param: :token
  resource :registration, only: %i[new create]
  resources :email_confirmations, only: %i[show new create], param: :token
  post "auth/google" => "auth_handoffs#create", as: :google_sign_in
  get "auth/google_oauth2/callback" => "omniauth_callbacks#create"
  get "auth/failure" => "omniauth_callbacks#failure"

  # My Account and re-auth (PRD §13, §15)
  resource :account, only: %i[show update]
  namespace :account do
    resource :email, only: %i[update destroy] do
      post :resend
    end
    resource :password, only: :update
    resource :sessions, only: :destroy
    resource :google_identity, only: :destroy
    resource :deletion, only: %i[show create]
  end
  resource :reauthentication, only: %i[show create] do
    post :code
  end

  # Households (PRD §12, §12a)
  resource :onboarding, only: :show
  resources :households, only: :create
  scope "h/:household_id", as: :household do
    get "/" => "households#show"
    resources :members, only: :index
    resource :settings, only: %i[show update], controller: "household_settings"
    resources :memberships, only: %i[update destroy] do
      post :leave, on: :collection
    end
    resource :ownership_transfer, only: %i[new create]
    resource :deletion, only: %i[new create], controller: "household_deletions"
    resources :invitations, only: :create, controller: "household_invitations" do
      member do
        post :resend
        post :revoke
      end
    end
  end
  resources :invitations, only: :index do
    member do
      post :accept
      post :decline
    end
  end
  get "invitations/:token" => "invitation_links#show", as: :invitation_link

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
    post "checks/backup" => "checks#run_backup", as: :run_backup
    get "charts" => "charts#show"
  end

  get "privacy" => "pages#privacy"
  root "pages#home"
end
