# app/controllers/connected_payments_controller.rb
class ConnectedPaymentsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_stripe
    before_action :set_connected_account!
  
    # GET /connected_payments
    #
    # Shows both:
    # - PaymentIntents (pi_*)
    # - Charges (ch_*)
    #
    # Notes:
    # - Uses CONNECTED ACCOUNT context via { stripe_account: acct_id }
    # - Avoids `dig` entirely (Stripe::StripeObject doesn't support it in many versions)
    # - Supports pagination via params[:pi_cursor], params[:ch_cursor]
    #
    def index
      # Optional filters
      limit = (params[:limit].presence || 20).to_i
      limit = 100 if limit > 100
      limit = 1   if limit < 1
  
      query = params[:q].to_s.strip.downcase
  
      # -------------------------
      # PaymentIntents
      # -------------------------
      pi_list = Stripe::PaymentIntent.list(
        {
          limit: limit,
          starting_after: params[:pi_cursor].presence
        },
        { stripe_account: @connected_acct_id }
      )
  
      @payment_intents = pi_list.data.map do |pi|
        build_payment_intent_row(pi)
      end
  
      @pi_next_cursor = pi_list.data.last&.id
      @pi_has_more    = !!pi_list.has_more
  
      # -------------------------
      # Charges
      # -------------------------
      ch_list = Stripe::Charge.list(
        {
          limit: limit,
          starting_after: params[:ch_cursor].presence
        },
        { stripe_account: @connected_acct_id }
      )
  
      @charges = ch_list.data.map do |ch|
        build_charge_row(ch)
      end
  
      @ch_next_cursor = ch_list.data.last&.id
      @ch_has_more    = !!ch_list.has_more
  
      # -------------------------
      # Simple local filter (optional)
      # -------------------------
      if query.present?
        @payment_intents.select! { |r| row_matches_query?(r, query) }
        @charges.select!         { |r| row_matches_query?(r, query) }
      end
  
      # Render your view: app/views/connected_payments/index.html.erb
    rescue Stripe::StripeError => e
      flash[:error] = e.message
      @payment_intents = []
      @charges = []
      @pi_has_more = @ch_has_more = false
    end
  
    private
  
    def set_stripe
      require "stripe"
      Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
    end
  
    def set_connected_account!
      # You can change this logic if you pick connected account by params[:acct_id]
      @connected_acct_id = current_user.try(:stripe_user_id)
  
      unless @connected_acct_id.present?
        redirect_to authenticated_root_path, alert: "Connected Stripe account missing."
      end
    end
  
    # -------------------------
    # Row builders (NO `dig`)
    # -------------------------
  
    def build_payment_intent_row(pi)
      # Try to show customer email if possible. PaymentIntent.customer is usually "cus_..."
      customer_label = "-"
      begin
        if pi.respond_to?(:customer) && pi.customer.present?
          cus = Stripe::Customer.retrieve(pi.customer, { stripe_account: @connected_acct_id })
          customer_label = cus.email.presence || cus.name.presence || cus.id
        end
      rescue Stripe::StripeError
        customer_label = pi.customer.to_s.presence || "-"
      end
  
      description =
        pi.description.presence ||
        (pi.respond_to?(:metadata) && pi.metadata && pi.metadata["description"].presence) ||
        "-"
  
      {
        type: "payment_intent",
        id: pi.id,
        amount: pi.amount,                 # integer cents
        currency: pi.currency,
        status: pi.status,
        created: Time.at(pi.created.to_i),
        customer: customer_label,
        payment_method: pi.payment_method.to_s.presence || "-",
        description: description,
        latest_charge: pi.latest_charge.to_s.presence || "-",
        livemode: !!pi.livemode
      }
    end
  
    def build_charge_row(ch)
      customer_label = "-"
      begin
        if ch.respond_to?(:customer) && ch.customer.present?
          cus = Stripe::Customer.retrieve(ch.customer, { stripe_account: @connected_acct_id })
          customer_label = cus.email.presence || cus.name.presence || cus.id
        end
      rescue Stripe::StripeError
        customer_label = ch.customer.to_s.presence || "-"
      end
  
      description =
        ch.description.presence ||
        (ch.respond_to?(:metadata) && ch.metadata && ch.metadata["description"].presence) ||
        "-"
  
      pm_label = "-"
      if ch.respond_to?(:payment_method_details) && ch.payment_method_details
        # e.g. { "card" => { "last4" => "4242", "brand" => "visa" }, "type" => "card" }
        type = ch.payment_method_details.type.to_s.presence
        if type == "card" && ch.payment_method_details.card
          brand = ch.payment_method_details.card.brand.to_s
          last4 = ch.payment_method_details.card.last4.to_s
          pm_label = [brand, ("•••• " + last4)].reject(&:blank?).join(" ")
        else
          pm_label = type.presence || "-"
        end
      end
  
      {
        type: "charge",
        id: ch.id,
        amount: ch.amount,                 # integer cents
        currency: ch.currency,
        status: ch.status,                 # "succeeded", "failed", etc.
        paid: !!ch.paid,
        refunded: !!ch.refunded,
        captured: !!ch.captured,
        created: Time.at(ch.created.to_i),
        customer: customer_label,
        payment_intent: ch.payment_intent.to_s.presence || "-",
        receipt_email: ch.receipt_email.to_s.presence || "-",
        payment_method: pm_label,
        description: description,
        livemode: !!ch.livemode
      }
    end
  
    def row_matches_query?(row, query)
      haystack = [
        row[:id],
        row[:status],
        row[:currency],
        row[:customer],
        row[:payment_method],
        row[:payment_intent],
        row[:description]
      ].compact.join(" ").downcase
  
      haystack.include?(query)
    end
  end
  