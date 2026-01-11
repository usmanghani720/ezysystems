# app/controllers/checkout_controller.rb
class CheckoutController < ApplicationController
    protect_from_forgery with: :exception
  
    def create
			user = User.find_by(id: params[:id])
      amount_cents = Integer(params.require(:amount_cents))
      currency = ENV["CURRENCY"]
  
      plan = Plan.find_by(amount_cents: amount_cents, currency: currency)
      return render json: { error: "Invalid plan amount" }, status: :unprocessable_entity unless plan
  
      session = Stripe::Checkout::Session.create(
        mode: "subscription",
        payment_method_types: ["card"],
        line_items: [{ price: plan.stripe_price_id, quantity: 1 }],
        customer_email: user.try(:email),
        subscription_data: {
          # 3-month free trial (90 days) or use trial_end below for exact 3 calendar months
          trial_period_days: 90
          # trial_end: 3.months.from_now.to_i
        },
        shipping_address_collection: {
          allowed_countries: ["US", "ID", "AU", "SG"]
        },
        success_url: "#{authenticated_root_url}/success?session_id={CHECKOUT_SESSION_ID}&vendor_id=#{user.try(:id)}",
        cancel_url:  "#{authenticated_root_url}/cancel",
        metadata: {
          plan_id: plan.id.to_s,
          amount_cents: plan.amount_cents.to_s,
          currency: plan.currency
        }
      )
  
      redirect_to session.url, allow_other_host: true
    rescue ArgumentError
      render json: { error: "amount_cents must be an integer" }, status: :unprocessable_entity
    end
  end
  