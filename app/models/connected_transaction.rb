# app/models/connected_transaction.rb
class ConnectedTransaction < ApplicationRecord
    validates :stripe_account_id, :payment_intent_id, :created_at_stripe, presence: true
end