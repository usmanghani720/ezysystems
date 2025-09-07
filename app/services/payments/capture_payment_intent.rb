# frozen_string_literal: true
module Payments
    class CapturePaymentIntent
      Result = Struct.new(:ok, :status, :message, keyword_init: true)
  
      # Capture some or all of the authorized amount.
      def self.call(payment_intent_id:, stripe_account:, idempotency_key:, amount_to_capture_cents: nil)
        args = {}
        args[:amount_to_capture] = amount_to_capture_cents if amount_to_capture_cents
  
        pi = Stripe::PaymentIntent.capture(
          payment_intent_id,
          args,
          { idempotency_key: idempotency_key, stripe_account: stripe_account }
        )
  
        Result.new(ok: true, status: pi.status)
      rescue Stripe::InvalidRequestError, Stripe::CardError => e
        Result.new(ok: false, status: "failed", message: e.message)
      end
    end
  end
  