# app/controllers/stripe_webhooks_controller.rb
class StripeWebhooksController < ApplicationController
  require "stripe"
  Stripe.api_key = ENV["STRIPE_SECRET_KEY"]

  skip_before_action :verify_authenticity_token

  def receive
    begin
      payload = request.body.read
      sig     = request.env["HTTP_STRIPE_SIGNATURE"]
      secret  = ENV["STRIPE_WEBHOOK_SECRET"]

      event = Stripe::Webhook.construct_event(payload, sig, secret)

      # Connected account id (acct_...) for Connect events
      connected_acct_id = event["account"]

      case event["type"]

      # ----------------------------
      # Existing EFW handler
      # ----------------------------
      when "radar.early_fraud_warning.created"
        early = event["data"]["object"]

        Payments::EarlyFraudAutoRefund.call(
          charge_id:         early["charge"],
          connected_acct_id: connected_acct_id,
          event_id:          event["id"],
          actionable:        early["actionable"]
        )

      # ---------------------------------------------------------
      # NEW: Save payment method after Setup Checkout completes
      # ---------------------------------------------------------
      when "checkout.session.completed"
        session = event["data"]["object"]

        if session["mode"] == "setup"
          stripe_customer_id = session["customer"]
          setup_intent_id    = session["setup_intent"]

          if stripe_customer_id.present? && setup_intent_id.present?
            local_customer = Customer.find_by(customer_id: stripe_customer_id)

            if local_customer.present?
              si = Stripe::SetupIntent.retrieve(
                setup_intent_id,
                { stripe_account: connected_acct_id }
              )

              pm_id = si["payment_method"]

              if pm_id.present?
                pm = Stripe::PaymentMethod.retrieve(
                  pm_id,
                  { stripe_account: connected_acct_id }
                )

                if pm.present? && pm["card"].present?
                  local_customer.update(payment_method: pm_id, last4: pm["card"]["last4"], brand: pm["card"]["brand"])
                end

                Stripe::Customer.update(
                  stripe_customer_id,
                  { invoice_settings: { default_payment_method: pm_id } },
                  { stripe_account: connected_acct_id }
                )
              else
                Rails.logger.warn("Webhook: SetupIntent has no payment_method (acct=#{connected_acct_id})")
              end
            else
              Rails.logger.warn("Webhook: Local customer not found (cus=#{stripe_customer_id}, acct=#{connected_acct_id})")
            end
          else
            Rails.logger.warn("Webhook: Missing customer or setup_intent (acct=#{connected_acct_id})")
          end
        end
      end

    rescue Stripe::SignatureVerificationError => e
      Rails.logger.error("Stripe webhook signature error: #{e.message}")

    rescue JSON::ParserError => e
      Rails.logger.error("Stripe webhook JSON error: #{e.message}")

    rescue => e
      # Catch ALL unexpected errors
      Rails.logger.error("Stripe webhook unexpected error: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))

    ensure
      # Always return 200 so Stripe does not retry endlessly
      head :ok
    end
  end
end
