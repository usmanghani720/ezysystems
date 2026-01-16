# app/controllers/stripe_webhooks_controller.rb
class StripeWebhooksController < ApplicationController
  require "stripe"

  # Stripe webhooks are external POSTs; skip CSRF verification
  #skip_before_action :verify_authenticity_token

  # POST /stripe/webhook (or whatever route points here)
  def receive
    Stripe.api_key = ENV.fetch("STRIPE_SECRET_KEY")

    payload = request.body.read
    sig     = request.env["HTTP_STRIPE_SIGNATURE"]
    secret  = ENV.fetch("STRIPE_WEBHOOK_SECRET") # platform webhook signing secret

    event = Stripe::Webhook.construct_event(payload, sig, secret)

    # For Connect events, Stripe sets event.account to the connected account id
    connected_acct_id = event.account

    case event.type
    # ------------------------------------------------------------------
    # EXISTING LOGIC: Early Fraud Warning -> your service object
    # ------------------------------------------------------------------
    when "radar.early_fraud_warning.created"
      early      = event.data.object
      charge_id  = early.charge
      actionable = early.actionable

      Payments::EarlyFraudAutoRefund.call(
        charge_id:         charge_id,
        connected_acct_id: connected_acct_id,
        event_id:          event.id,
        actionable:        actionable
      )

    # ------------------------------------------------------------------
    # NEW LEDGER LOGIC: Keep ConnectedTransaction in sync
    # ------------------------------------------------------------------
    when "payment_intent.succeeded",
         "payment_intent.payment_failed",
         "payment_intent.canceled"
      upsert_connected_transaction_from_payment_intent!(
        payment_intent_id: event.data.object.id,
        connected_acct_id: connected_acct_id
      )

    when "charge.refunded"
      apply_charge_refunded!(event.data.object, connected_acct_id)

    when "refund.created"
      apply_refund_created!(event.data.object, connected_acct_id)

    else
      # Ignore other event types
    end

    head :ok
  rescue JSON::ParserError, Stripe::SignatureVerificationError => e
    Rails.logger.error("[StripeWebhook] Signature/payload error: #{e.message}")
    head :bad_request
  rescue => e
    # Return 500 so Stripe will retry on transient failures
    Rails.logger.error("[StripeWebhook] Handler error: #{e.class} #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
    head :internal_server_error
  end

  private

  # ------------------------------------------------------------------
  # Upsert a ConnectedTransaction row from a PaymentIntent
  # (Fetch expanded objects once here; keep UI fast)
  # ------------------------------------------------------------------
  def upsert_connected_transaction_from_payment_intent!(payment_intent_id:, connected_acct_id:)
    return unless connected_acct_id.present?

    pi = Stripe::PaymentIntent.retrieve(
      {
        id: payment_intent_id,
        expand: ["customer", "payment_method", "latest_charge"]
      },
      { stripe_account: connected_acct_id }
    )

    charge = pi.latest_charge
    pm     = pi.payment_method
    card   = pm&.card

    ConnectedTransaction.upsert(
      {
        stripe_account_id: connected_acct_id,
        payment_intent_id: pi.id,
        charge_id: charge&.id,

        amount: pi.amount,
        currency: pi.currency&.upcase,
        status: pi.status,

        customer_email: (pi.customer&.respond_to?(:email) ? pi.customer.email : nil),
        payment_method_label: (card ? "#{card.brand&.upcase} •••• #{card.last4}" : nil),

        refunded: (charge ? (charge.refunded || charge.amount_refunded.to_i > 0) : false),
        amount_refunded: (charge ? charge.amount_refunded.to_i : 0),

        created_at_stripe: pi.created.to_i,
        updated_at: Time.current,
        created_at: Time.current
      },
      unique_by: :payment_intent_id
    )
  end

  # ------------------------------------------------------------------
  # Update ledger on charge.refunded
  # ------------------------------------------------------------------
  def apply_charge_refunded!(charge, connected_acct_id)
    return unless connected_acct_id.present?
    return unless charge&.id.present?

    ConnectedTransaction.where(charge_id: charge.id).update_all(
      refunded: (charge.refunded || charge.amount_refunded.to_i > 0),
      amount_refunded: charge.amount_refunded.to_i,
      updated_at: Time.current
    )
  end

  # ------------------------------------------------------------------
  # Update ledger on refund.created (fallback)
  # ------------------------------------------------------------------
  def apply_refund_created!(refund, connected_acct_id)
    return unless connected_acct_id.present?
    return unless refund&.charge.present?

    ConnectedTransaction.where(charge_id: refund.charge).update_all(
      refunded: true,
      updated_at: Time.current
    )
  end
end
