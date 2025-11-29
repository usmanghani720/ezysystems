# app/controllers/stripe_webhooks_controller.rb
class StripeWebhooksController < ApplicationController
    require "stripe"
    Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
  
    def receive
      payload = request.body.read
      sig     = request.env["HTTP_STRIPE_SIGNATURE"]
      secret  = ENV["STRIPE_WEBHOOK_SECRET"] # platform webhook secret
  
      event = Stripe::Webhook.construct_event(payload, sig, secret)
  
      # This is the connected account that the charge lives on
      connected_acct_id = event["account"]
  
      case event["type"]
      when "radar.early_fraud_warning.created"
        early = event["data"]["object"]
        charge_id = early["charge"]
        actionable = early["actionable"] # true when you can still take action to avoid dispute
  
        # Optional: only auto-refund for sellers who opted in
        # seller = User.find_by(stripe_user_id: connected_acct_id)
        # return head(:ok) unless seller&.auto_refund_on_efw?
  
        Payments::EarlyFraudAutoRefund.call(
          charge_id:         charge_id,
          connected_acct_id: connected_acct_id,
          event_id:          event["id"],
          actionable:        actionable
        )
      end
  
      head :ok
    rescue JSON::ParserError, Stripe::SignatureVerificationError => e
      Rails.logger.error("Webhook error: #{e.message}")
      head :bad_request
    end
  end
  