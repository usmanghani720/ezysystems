# app/services/payments/early_fraud_auto_refund.rb
module Payments
    class EarlyFraudAutoRefund
			require "stripe"
			Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
      def self.call(charge_id:, connected_acct_id:, event_id:, actionable: true)
        # Idempotency so we never double-refund on re-delivery
        idem_key = "efw-autorefund-#{charge_id}-#{event_id}"
  
        # Look up the charge on the connected account

        if !connected_acct_id.blank?
          ch = Stripe::Charge.retrieve(
            charge_id,
            { stripe_account: connected_acct_id }
          )
        else   
          ch = Stripe::Charge.retrieve(
            charge_id
          )
        end
        # If already refunded, stop
        return if ch["refunded"] || (ch["refunds"] && ch["refunds"]["total_count"].to_i > 0)
  
        # If the payment is from a PaymentIntent, fetch its status
        pi = nil
        if ch["payment_intent"].present?
          if !connected_acct_id.blank?
            pi = Stripe::PaymentIntent.retrieve(
              ch["payment_intent"],
              { stripe_account: connected_acct_id }
            )
          else   
            pi = Stripe::PaymentIntent.retrieve(
              ch["payment_intent"]
            )
          end
        end
  
        # 1) AUTH-ONLY case (manual capture): cancel to release the hold
        if pi && pi["status"] == "requires_capture"
          if !connected_acct_id.blank?
            Stripe::PaymentIntent.cancel(
              pi["id"],
              { cancellation_reason: "requested_by_customer" },
              { stripe_account: connected_acct_id }
            )
          else  
            Stripe::PaymentIntent.cancel(
              pi["id"],
              { cancellation_reason: "requested_by_customer" }
            )
          end
          Rails.logger.info("[EFW] Canceled uncaptured PI #{pi['id']} for #{charge_id}")
          return
        end
  
        # 2) CAPTURED (or succeeded) → full refund on the connected account
        # Try to reverse transfers / app fee if using destination charges; if invalid, Stripe will raise.
        refund_params = {
          charge:  charge_id,
          reason:  "requested_by_customer",
          metadata: { auto_refund: "early_fraud_warning", efw_event_id: event_id }
        }
  
        begin
          if !connected_acct_id.blank?
            Stripe::Refund.create(
              refund_params,
              { idempotency_key: idem_key, stripe_account: connected_acct_id }
            )
            
            UserMailer.send_early_fraud_warning_email_to_admin(connected_acct_id).deliver_now
          else  
            Stripe::Refund.create(
              refund_params,
              { idempotency_key: idem_key }
            )
            
            #UserMailer.send_early_fraud_warning_email_to_admin(connected_acct_id).deliver_now
          end

        rescue Stripe::InvalidRequestError => e
          # If parameters like reverse_transfer/refund_application_fee are invalid for your flow,
          # create a plain refund without them (we're already not including them by default).
          raise unless e.message.to_s =~ /already been refunded|has no captured balance|cancellation/i
        end

        if !connected_acct_id.blank?
          Rails.logger.info("[EFW] Refunded charge #{charge_id} on acct #{connected_acct_id}")
        else  
          Rails.logger.info("[EFW] Refunded charge #{charge_id}")
        end
  
        # 3) If you took a PLATFORM application fee on this charge, refund it separately (platform account).
        # (Stripe processing fees are generally not refundable; this is your *application* fee.)
        begin
          fees = Stripe::ApplicationFee.list(charge: charge_id) # platform scope (no stripe_account here)
          fee  = fees.data.first
          if fee
            # Newer SDKs:
            Stripe::ApplicationFeeRefund.create(fee: fee.id)
            # (Older SDKs also support: Stripe::ApplicationFee.create_refund(fee.id))
            Rails.logger.info("[EFW] Refunded app fee #{fee.id} for charge #{charge_id}")
          end
        rescue => e
          Rails.logger.warn("[EFW] App fee refund skipped: #{e.message}")
        end
      end
    end
  end
  