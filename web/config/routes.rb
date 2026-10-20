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
  resource :avatar, only: %i[update destroy]
  get "avatars/:user_id" => "avatars#show", as: :user_avatar
  namespace :account do
    resource :email, only: %i[update destroy] do
      post :resend
    end
    resource :password, only: :update
    resources :notification_preferences, only: :update, param: :household_id
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
    resources :member_devices, only: :destroy
    resource :settings, only: %i[show update], controller: "household_settings"
    resources :memberships, only: %i[update destroy] do
      post :leave, on: :collection
    end
    get "upcoming" => "upcoming#show", as: :upcoming
    resource :dashboard, only: :show do
      get :drilldown, to: "dashboards/drilldowns#show"
    end
    resources :reminder_deliveries, only: :index do
      post :resend, on: :member
      post :send_by_email, on: :member
      post :resend_all, on: :collection
    end
    resources :records do
      resources :photos, only: %i[create destroy]
      get "photos/:id(/:variant)" => "photos#show", as: :photo_file
      member do
        get :mark_paid
        post :mark_paid
        post :snooze, to: "snoozes#create"
        delete :snooze, to: "snoozes#destroy"
        post :restart_reminders
        get :done
      end
    end
    resources :imports, only: %i[new create show] do
      post :commit, on: :member
      post :undo, on: :member
    end
    resources :recurring_templates, path: "templates", except: :show do
      post :link, on: :member
    end
    resources :categories, except: :show do
      post :archive, on: :member
      delete "aliases/:alias_id" => "categories#destroy_alias", on: :collection, as: :destroy_alias
    end
    resources :payment_methods, except: %i[show destroy] do
      post :archive, on: :member
      get :from_notes, on: :collection
      post :from_notes, on: :collection, action: :assign_from_notes
    end
    resource :ownership_transfer, only: %i[new create]
    resource :deletion, only: %i[new create], controller: "household_deletions"
    resource :record_purge, only: %i[new create]
    resources :invitations, only: :create, controller: "household_invitations" do
      member do
        post :resend
        post :revoke
      end
    end
  end
  delete "push_subscriptions/current" => "push_subscriptions#destroy_current"
  resources :push_subscriptions, only: %i[create destroy]
  post "push_receipts/:token" => "push_receipts#create", as: :push_receipt
  resources :notifications, only: :index do
    post :read_all, on: :collection
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
  get "guide" => "pages#guide"
  patch "locale" => "locales#update"
  root "pages#home"
end
