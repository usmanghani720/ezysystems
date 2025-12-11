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
  post 'payment/update_user_3d', to: 'payments#update_user_3d', as: 'update_user_3d' 
  post 'payment/remove_customer', to: 'payments#remove_customer', as: 'remove_customer' 

  get 'balance/:id', to: 'payments#balance', as: 'balance'
  post 'set_minimum_balance', to: 'payments#set_minimum_balance', as: 'set_minimum_balance' 

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
  get "/custom_portal", to: "home#custom_portal", as: :custom_portal
  get "/customer_messaging", to: "home#customer_messaging", as: :customer_messaging
  get "/marketing_tools", to: "home#marketing_tools", as: :marketing_tools
  get "/marketing_messaging", to: "home#marketing_messaging", as: :marketing_messaging
  get "/payment", to: "home#payment", as: :payment
  get "/invoicing", to: "home#invoicing", as: :invoicing
  get "/expenses", to: "home#expenses", as: :expenses
  get "/bookkeeping", to: "home#bookkeeping", as: :bookkeeping
  get "/customer_management", to: "home#customer_management", as: :customer_management
  get "/jobs", to: "home#jobs", as: :jobs
  get "/assignment_scheduling", to: "home#assignment_scheduling", as: :assignment_scheduling
  get "/job_records", to: "home#job_records", as: :job_records
  get "/professional_window_cleaner_software", to: "home#professional_window_cleaner_software", as: :professional_window_cleaner_software
  get "/bin_cleaning_software", to: "home#bin_cleaning_software", as: :bin_cleaning_software
  get "/carpet_cleaning_software", to: "home#carpet_cleaning_software", as: :carpet_cleaning_software
  get "/exterior_cleaning", to: "home#exterior_cleaning", as: :exterior_cleaning
  get "/cleaning_housekeeping_maid_service_software", to: "home#cleaning_housekeeping_maid_service_software", as: :cleaning_housekeeping_maid_service_software
  get "/mobile_cleaning_services", to: "home#mobile_cleaning_services", as: :mobile_cleaning_services
  get "/other_services", to: "home#other_services", as: :other_services
  get "/blog", to: "home#blog", as: :blog
  # get 'create_payment/:id', to: 'payments#create_payment', as: 'create_payment'
  # post 'make_payment/:id', to: 'payments#make_payment', as: 'make_payment'
  
  resources :charges, only: [:new, :create]
  resources :stripe, only: [:new]
  get "stripe/connect", to: "stripe#connect", as: :stripe_connect

  # Maintenance fallback route for all unmatched paths
  match "*unmatched", to: "home#maintenance", via: :all


  authenticated :user do
    root to: "payments#new", as: :authenticated_root
  end

  unauthenticated do
    root to: "home#index", as: :unauthenticated_root
  end
end