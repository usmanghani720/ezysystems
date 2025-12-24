# app/controllers/connected_payments_controller.rb
class ConnectedPaymentsController < ApplicationController
    before_action :authenticate_user!
  
    def index
      connected_acct_id = current_user.stripe_user_id
      raise "Connected Stripe account missing" unless connected_acct_id.present?
  
      @view_type = params[:view].presence_in(%w[payment_intents charges]) || "payment_intents"
      @status    = params[:status].presence || "all"
      @limit     = [[params[:limit].to_i, 10].max, 100].min
      @limit     = 25 if @limit.zero?
      @after     = params[:starting_after].presence
  
      case @view_type
      when "charges"
        load_charges!(connected_acct_id)
      else
        load_payment_intents!(connected_acct_id)
      end
    rescue Stripe::StripeError => e
      flash.now[:error] = e.message
      @rows = []
      @has_more = false
    rescue => e
      flash.now[:error] = e.message
      @rows = []
      @has_more = false
    end
  
    private
  
    def load_payment_intents!(connected_acct_id)
      list_params = { limit: @limit, starting_after: @after }.compact
  
      # Stripe supports these statuses in list filtering:
      # succeeded, processing, requires_action, canceled (others exist, but these match your UI best)
      list_params[:status] = @status if %w[succeeded processing requires_action canceled].include?(@status)
  
      intents = Stripe::PaymentIntent.list(
        list_params.merge(
          expand: [
            "data.customer",
            "data.payment_method",
            "data.latest_charge",
            "data.latest_charge.billing_details"
          ]
        ),
        { stripe_account: connected_acct_id }
      )
  
      raw = intents.data
  
      # Custom "failed" bucket (Stripe doesn't provide `status=failed` for PIs)
      filtered =
        if @status == "failed"
          raw.select { |pi| pi.status == "requires_payment_method" || pi.status == "canceled" }
        else
          raw
        end
  
      @rows = filtered.map do |pi|
        pm = pi.payment_method
        card = pm&.card
        pm_label = card ? "#{card.brand.to_s.upcase} •••• #{card.last4}" : (pm&.type || "-")
  
        cust = pi.customer
        cust_label =
          if cust.respond_to?(:email) && cust.email.present?
            cust.email
          else
            pi.metadata&.dig("customer_email") || "-"
          end
  
        desc = pi.description.presence || pi.metadata&.dig("description") || "-"
  
        {
          id: pi.id,
          amount: (pi.amount || 0),
          currency: (pi.currency || "usd"),
          status: pi.status,
          payment_method: pm_label,
          description: desc,
          customer: cust_label,
          created: pi.created
        }
      end
  
      @has_more = intents.has_more
      @next_starting_after = raw.last&.id
    end
  
    def load_charges!(connected_acct_id)
      list_params = { limit: @limit, starting_after: @after }.compact
  
      # Charges list supports status filtering via `paid` and `refunded` better than "status"
      # We'll filter in Ruby for a Stripe-dashboard-like experience.
      charges = Stripe::Charge.list(
        list_params.merge(
          expand: [
            "data.customer",
            "data.payment_method_details",
            "data.billing_details"
          ]
        ),
        { stripe_account: connected_acct_id }
      )
  
      raw = charges.data
  
      filtered =
        case @status
        when "succeeded"
          raw.select { |ch| ch.paid == true && ch.status == "succeeded" }
        when "failed"
          raw.select { |ch| ch.status == "failed" }
        when "refunded"
          raw.select { |ch| ch.refunded == true }
        when "all", nil
          raw
        else
          raw
        end
  
      @rows = filtered.map do |ch|
        pmd = ch.payment_method_details
        card = pmd&.card
        pm_label =
          if card
            "#{card.brand.to_s.upcase} •••• #{card.last4}"
          else
            pmd&.type || "-"
          end
  
        cust = ch.customer
        cust_label =
          if cust.respond_to?(:email) && cust.email.present?
            cust.email
          else
            ch.billing_details&.email || "-"
          end
  
        desc = ch.description.presence || "-"
  
        {
          id: ch.id,
          amount: (ch.amount || 0),
          currency: (ch.currency || "usd"),
          status: ch.status,              # succeeded/failed/pending
          payment_method: pm_label,
          description: desc,
          customer: cust_label,
          created: ch.created
        }
      end
  
      @has_more = charges.has_more
      @next_starting_after = raw.last&.id
    end
  end
  