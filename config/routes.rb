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
  get 'connected_receipts/:id', to: 'connected_receipts#show', as: 'connected_receipt'
  post 'payment/create_payout', to: 'payments#create_payout', as: 'create_payout' 
  get 'payment/payouts', to: 'payments#payouts', as: 'payouts' 
  get 'payout', to: 'payments#payout', as: 'payout'
  post 'payment/create_small_payout', to: 'payments#create_small_payout', as: 'create_small_payout' 
  post 'payment/update_user_status', to: 'payments#update_user_status', as: 'update_user_status' 
  resources :charges, only: [:create]

  get 'create_payment/:id', to: 'payments#create_payment', as: 'create_payment'
  post 'make_payment/:id', to: 'payments#make_payment', as: 'make_payment'
  
  resources :charges, only: [:new, :create]
  resources :stripe, only: [:new]
  get "stripe/connect", to: "stripe#connect", as: :stripe_connect
  root to: 'payments#new'
end