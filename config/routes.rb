Rails.application.routes.draw do
  devise_for :admin_users, ActiveAdmin::Devise.config
  devise_for :users, controllers: { sessions: 'sessions', registrations: 'registrations' }
  ActiveAdmin.routes(self)
  resources :payments, only: [:new, :create]
  get 'payments/new'
  get 'users', to: 'payments#all_users', as: 'users'
  get 'customers', to: 'payments#customers', as: 'customers'
  get 'new_customer', to: 'payments#new_customer', as: 'new_customer'
  post 'create_customer', to: 'payments#create_customer', as: 'create_customer'
  get 'payment/create_express_account', to: 'payments#create_express_account', as: 'create_express_account' 
  get 'payment/create_standard_account', to: 'payments#create_standard_account', as: 'create_standard_account' 
  get 'invoice', to: 'payments#invoice', as: 'invoice' 
  get 'success', to: 'payments#success', as: 'success' 
  get 'cancel', to: 'payments#cancel', as: 'cancel' 
  get 'invoices', to: 'payments#invoices', as: 'invoices' 
  post 'create_payment_link', to: 'payments#create_payment_link', as: 'create_payment_link' 
  get 'charge/:id', to: 'charges#new', as: 'charge'
  get 'response', to: 'charges#response', as: 'response'
  post 'handle_payment_methods', to: 'charges#handle_payment_methods'
  get 'handle_payment_methods_confirm', to: 'charges#handle_payment_methods_confirm'
  post 'payment/create_payout', to: 'payments#create_payout', as: 'create_payout' 
  get 'payment/payouts', to: 'payments#payouts', as: 'payouts' 
  get 'payout', to: 'payments#payout', as: 'payout'
  get 'customer_creation_success', to: 'payments#customer_creation_success', as: 'customer_creation_success'
  post 'payment/create_small_payout', to: 'payments#create_small_payout', as: 'create_small_payout' 
  post 'payment/update_user_status', to: 'payments#update_user_status', as: 'update_user_status' 
  post 'payment/remove_customer', to: 'payments#remove_customer', as: 'remove_customer' 

  get 'new_payment_link', to: 'payments#new_payment_link', as: 'new_payment_link'
  post 'create_custom_payment_link', to: 'payments#create_custom_payment_link', as: 'create_custom_payment_link' 
  # Amount form + charge
  get  "/create_payment/:id", to: "customers#create_payment_form",  as: :create_payment_form
  post "/create_payment/:id", to: "customers#create_payment",       as: :create_payment

  # SCA auth page (you'll email/share this link with the customer when needed)
  get  "/payments/authenticate", to: "payments#authenticate",       as: :authenticate_payment

  # Update/Add card via Checkout (mode: setup)
  get  "/payment_methods/new",     to: "payment_methods#new",       as: :new_payment_method
  get  "/payment_methods/success", to: "payment_methods#success",   as: :payment_method_success

  get  "/capture_ui",          to: "payments#capture_ui",  as: :capture_ui
  post "/capture_payment_intent", to: "payments#capture",  as: :capture_payment_intent

  post "/stripe/webhooks", to: "stripe_webhooks#receive"

  resources :charges, only: [:create]

  get  "/contact",          to: "home#contact",  as: :contact
  get "/privacy", to: "home#privacy", as: :privacy
  get "/terms", to: "home#terms", as: :terms
  get "/pricing", to: "home#pricing", as: :pricing

  # get 'create_payment/:id', to: 'payments#create_payment', as: 'create_payment'
  # post 'make_payment/:id', to: 'payments#make_payment', as: 'make_payment'
  
  resources :charges, only: [:new, :create]
  resources :stripe, only: [:new]
  get "stripe/connect", to: "stripe#connect", as: :stripe_connect

  authenticated :user do
    root to: "payments#new", as: :authenticated_root
  end

  unauthenticated do
    root to: "home#index", as: :unauthenticated_root
  end
end