# app/controllers/connected_payments_controller.rb
class ConnectedPaymentsController < ApplicationController
    before_action :authenticate_user!
  
    def index
      Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
  
      @status = params[:status].presence || "all"
  
      # Per-page (limit)
      @limit = params[:limit].to_i
      @limit = 25 if @limit <= 0
      @limit = 100 if @limit > 100
  
      # Stripe cursor params (only one should be present)
      @starting_after = params[:starting_after].presence
      @ending_before  = params[:ending_before].presence
  
      # Admin sees ALL vendors (loop through connected accounts)
      # Vendor sees only own connected account.
      if current_user.role == "admin"
        load_admin_rows!
      else
        connected_acct_id = current_user.stripe_user_id
        raise "Connected Stripe account missing" unless connected_acct_id.present?
        load_rows_for_account!(connected_acct_id)
      end
    rescue Stripe::StripeError => e
      flash.now[:error] = e.message
      @rows = []
      @has_more = false
      @first_id = nil
      @last_id = nil
    rescue => e
      flash.now[:error] = e.message
      @rows = []
      @has_more = false
      @first_id = nil
      @last_id = nil
    end
  
    private
  
    # ---------------------------
    # Vendor / single connected acct
    # ---------------------------
    def load_rows_for_account!(connected_acct_id)
      list_params = {
        limit: @limit
      }
  
      # Stripe cursor paging
      if @starting_after.present?
        list_params[:starting_after] = @starting_after
      elsif @ending_before.present?
        list_params[:ending_before] = @ending_before
      end
  
      # We build ONE combined table from PaymentIntents.
      # PaymentIntent has latest_charge -> represents the successful charge if it exists.
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
  
      # Optional status filtering in Ruby (because PI list status filter is limited)
      filtered =
        case @status
        when "succeeded"
          raw.select { |pi| pi.status == "succeeded" }
        when "failed"
          raw.select { |pi| pi.status == "requires_payment_method" || pi.status == "canceled" }
        when "processing"
          raw.select { |pi| pi.status == "processing" }
        when "requires_action"
          raw.select { |pi| pi.status == "requires_action" }
        when "canceled"
          raw.select { |pi| pi.status == "canceled" }
        else
          raw
        end
  
      @rows = filtered.map { |pi| row_from_pi(pi, connected_acct_id) }
  
      # For Prev/Next buttons
      @has_more = intents.has_more
      @first_id = raw.first&.id
      @last_id  = raw.last&.id
    end
  
    # ---------------------------
    # Admin / aggregate ALL vendors
    # ---------------------------
    def load_admin_rows!
      # You need a way to fetch all vendor stripe_user_id values.
      # Example: User.where(role: "vendor").where.not(stripe_user_id: nil)
      vendor_accounts = User.where(role: "vendor").where.not(stripe_user_id: [nil, ""]).pluck(:stripe_user_id)
  
      # Admin may also have their own connected acct and want to act as vendor too:
      if current_user.stripe_user_id.present?
        vendor_accounts << current_user.stripe_user_id
      end
      vendor_accounts.uniq!
  
      rows = []
  
      vendor_accounts.each do |acct_id|
        # NOTE: cursor paging across multiple accounts cannot be truly “global next page”
        # without storing cursors per account. So for admin, we usually fetch a fixed small
        # batch per account and merge-sort.
        intents = Stripe::PaymentIntent.list(
          {
            limit: 25,
            expand: [
              "data.customer",
              "data.payment_method",
              "data.latest_charge",
              "data.latest_charge.billing_details"
            ]
          },
          { stripe_account: acct_id }
        )
  
        intents.data.each do |pi|
          rows << row_from_pi(pi, acct_id)
        end
      end
  
      # Sort merged rows newest-first (IMPORTANT)
      rows.sort_by! { |r| -r[:created].to_i }
  
      # Apply filter after merge
      @rows =
        case @status
        when "succeeded"       then rows.select { |r| r[:status] == "succeeded" }
        when "failed"          then rows.select { |r| %w[requires_payment_method canceled].include?(r[:status]) }
        when "processing"      then rows.select { |r| r[:status] == "processing" }
        when "requires_action" then rows.select { |r| r[:status] == "requires_action" }
        when "canceled"        then rows.select { |r| r[:status] == "canceled" }
        else
          rows
        end
  
      # Admin merged pagination (simple)
      @rows = @rows.first(@limit)
  
      # For admin merged list, Prev/Next would require a separate design.
      # Keep them disabled to avoid wrong paging.
      @has_more = false
      @first_id = nil
      @last_id  = nil
    end
  
    def row_from_pi(pi, connected_acct_id)
      pm = pi.payment_method
      card = pm&.card
      pm_label = card ? "#{card.brand.to_s.upcase} •••• #{card.last4}" : (pm&.type || "-")
  
      cust = pi.customer
      cust_label =
        if cust.respond_to?(:email) && cust.email.present?
          cust.email
        else
          pi.metadata&.[]("customer_email") || "-"
        end
  
      charge = pi.latest_charge
      ch_id  = charge&.id
  
      desc = pi.description.presence || pi.metadata&.[]("description") || (charge&.description.presence) || "-"
  
      {
        id: pi.id,
        connected_account: connected_acct_id,
        amount: pi.amount || 0,
        currency: pi.currency || "usd",
        status: pi.status,
        payment_method: pm_label,
        description: desc,
        customer: cust_label,
        created: pi.created,
        charge_id: ch_id
      }
    end
  end
  