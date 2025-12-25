# app/controllers/connected_payments_controller.rb
class ConnectedPaymentsController < ApplicationController
  before_action :authenticate_user!

  DEFAULT_LIMIT = 10
  MAX_LIMIT     = 100

  def index
    @status = params[:status].presence || "all"
    @limit  = [[params[:limit].to_i, DEFAULT_LIMIT].max, MAX_LIMIT].min
    @page   = params[:page].to_i.positive? ? params[:page].to_i : 1

    if current_user.role == "admin"
      load_admin_rows!
    else
      load_vendor_rows!
    end
  rescue Stripe::StripeError => e
    flash.now[:error] = e.message
    @rows = []
    @has_more = false
  end

  private

  # ------------------------------------------------------------
  # ADMIN: all connected accounts
  # ------------------------------------------------------------
  def load_admin_rows!
    account_ids = User.where.not(stripe_user_id: [nil, ""])
                      .pluck(:stripe_user_id)
                      .uniq

    all_rows = []

    account_ids.each do |acct|
      pis = Stripe::PaymentIntent.list(
        {
          limit: MAX_LIMIT,
          expand: [
            "data.customer",
            "data.payment_method",
            "data.latest_charge"
          ]
        },
        { stripe_account: acct }
      )

      pis.data.each do |pi|
        next unless status_match?(pi)

        all_rows << normalize_pi(pi, acct)
      end
    end

    all_rows.sort_by! { |r| -r[:created] }

    paginate!(all_rows)
  end

  # ------------------------------------------------------------
  # VENDOR: single connected account
  # ------------------------------------------------------------
  def load_vendor_rows!
    acct = current_user.stripe_user_id
    raise "Connected Stripe account missing" unless acct.present?

    pis = Stripe::PaymentIntent.list(
      {
        limit: MAX_LIMIT,
        expand: [
          "data.customer",
          "data.payment_method",
          "data.latest_charge"
        ]
      },
      { stripe_account: acct }
    )

    rows = pis.data
              .select { |pi| status_match?(pi) }
              .map { |pi| normalize_pi(pi, acct) }
              .sort_by { |r| -r[:created] }

    paginate!(rows)
  end

  # ------------------------------------------------------------
  # Pagination (page numbers, DataTables style)
  # ------------------------------------------------------------
  def paginate!(rows)
    offset = (@page - 1) * @limit
    @total_count = rows.size
    @rows = rows.slice(offset, @limit) || []

    @total_pages = (@total_count / @limit.to_f).ceil
  end

  # ------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------
  def status_match?(pi)
    return true if @status == "all"

    case @status
    when "succeeded"
      pi.status == "succeeded"
    when "failed"
      %w[canceled requires_payment_method].include?(pi.status)
    when "processing"
      pi.status == "processing"
    when "requires_action"
      pi.status == "requires_action"
    when "canceled"
      pi.status == "canceled"
    else
      true
    end
  end

  def normalize_pi(pi, acct)
    pm = pi.payment_method
    card = pm&.card

    {
      id: pi.id,
      amount: pi.amount,
      currency: pi.currency&.upcase || "USD",
      status: pi.status,
      payment_method: card ? "#{card.brand.upcase} •••• #{card.last4}" : "-",
      description: pi.description.presence || pi.metadata["description"] || "-",
      customer: pi.customer&.email || "-",
      created: pi.created,
      created_at: Time.at(pi.created).strftime("%b %d, %Y %I:%M %p"),
      stripe_account: acct
    }
  end
end
