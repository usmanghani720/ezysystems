# frozen_string_literal: true
class Payments::OffSessionCharge
  SOFT_DECLINES = %w[
    insufficient_funds
    issuer_unavailable
    processing_error
    try_again_later
    generic_decline
  ].freeze

  Result = Struct.new(
    :ok, :status, :payment_intent_id, :client_secret, :decline_code, :message, :soft_decline,
    keyword_init: true
  )

  def self.call(customer_id:, payment_method_id:, amount_cents:, currency:, idempotency_key:, stripe_account:, description: nil, metadata: {})
    intent = Stripe::PaymentIntent.create(
      {
        amount: amount_cents,
        currency: currency,
        customer: customer_id,
        payment_method: payment_method_id,
        off_session: true,   # 💡 charge without the customer present
        confirm: true,       # immediately confirm
        description: description,
        metadata: metadata
      },
      {
        idempotency_key: idempotency_key,
        stripe_account: stripe_account
      }
    )

    Result.new(ok: true, status: intent.status, payment_intent_id: intent.id)
  rescue Stripe::CardError => e
    err = e.error
    pi  = err.payment_intent

    Result.new(
      ok: false,
      status: (pi&.status == "requires_action" || err.code == "authentication_required") ? "requires_action" : "failed",
      payment_intent_id: pi&.id,
      client_secret: pi&.client_secret,
      decline_code: err.decline_code,
      message: err.message,
      soft_decline: SOFT_DECLINES.include?(err.decline_code.to_s)
    )
  end
end
