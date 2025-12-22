# frozen_string_literal: true
module Payments
  class OffSessionAuthorize
    require "stripe"
    Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
    Result = Struct.new(:ok, :status, :payment_intent_id, :client_secret, :message, keyword_init: true)

    # Creates an off-session authorization (no funds captured yet).
    # Returns status "requires_capture" if auth holds were placed successfully.
    def self.call(customer_id:, payment_method_id:, amount_cents:, currency:, idempotency_key:, stripe_account:, description: nil, metadata: {}, force_3ds: false, shipping_name:, shipping_line1:, shipping_city:, shipping_state:, shipping_postal_code:, shipping_country:)
      create_args = {
        amount: amount_cents,
        currency: currency,
        customer: customer_id,
        payment_method: payment_method_id,
        off_session: true,          # customer not present
        confirm: true,              # perform the authorization now
        capture_method: "manual",   # <-- key difference: manual capture
        description: description,
        metadata: metadata,
        shipping: {
          name: shipping_name,
          address: {
            line1:       shipping_line1,
            city:        shipping_city,
            state:       shipping_state,
            postal_code: shipping_postal_code,
            country:     shipping_country
          }
        },
      }
      create_args[:payment_method_options] = { card: { request_three_d_secure: "any" } } if force_3ds

      pi = Stripe::PaymentIntent.create(
        create_args,
        { idempotency_key: idempotency_key, stripe_account: stripe_account }
      )

      # Success path:
      #   - "requires_capture"  => auth placed, ready to capture later
      #   - "succeeded"         => (rare with manual capture) would mean already captured
      Result.new(ok: true, status: pi.status, payment_intent_id: pi.id)
    rescue Stripe::CardError => e
      err = e.error
      pi  = err.payment_intent
      # If SCA is needed, you'll get requires_action off-session
      Result.new(
        ok: false,
        status: (pi&.status == "requires_action" || err.code == "authentication_required") ? "requires_action" : "failed",
        payment_intent_id: pi&.id,
        client_secret: pi&.client_secret,
        message: err.message
      )
    end
  end
end
