class Plan < ApplicationRecord
    validates :name, :amount_cents, :currency, :stripe_product_id, :stripe_price_id, presence: true
    validates :amount_cents, numericality: { greater_than: 0 }
end