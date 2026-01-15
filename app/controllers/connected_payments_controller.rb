# app/controllers/connected_payments_controller.rb
class ConnectedPaymentsController < ApplicationController
  before_action :authenticate_user!

  DEFAULT_LIMIT = 10
  MAX_LIMIT     = 100

  # ------------------------------------------------------------
  # INDEX: read from local DB (ConnectedTransaction), not Stripe
  # ------------------------------------------------------------
  def index
    @status = params[:status].presence || "all"
    @limit  = [[params[:limit].to_i, DEFAULT_LIMIT].max, MAX_LIMIT].min
    @page   = params[:page].to_i.positive? ? params[:page].to_i : 1

    scope = ConnectedTransaction.all

    if current_user.role == "admin"
      # Admin can see all transactions across all connected accounts
      # (Optionally add filters like stripe_account_id, date range, etc.)
    else
      acct = current_user.stripe_user_id
      raise "Connected Stripe account missing" unless acct.present?
      scope = scope.where(stripe_account_id: acct)
    end

    scope = apply_status_filter(scope, @status)

    @total_count = scope.count
    @total_pages = (@total_count / @limit.to_f).ceil

    @rows = scope
      .order(created_at_stripe: :desc)
      .offset((@page - 1) * @limit)
      .limit(@limit)
      .map { |t| normalize_tx_row(t) }

  rescue => e
    flash.now[:error] = e.message
    @rows = []
    @total_count = 0
    @total_pages = 0
  end

  # ------------------------------------------------------------
  # REFUND: still done live via Stripe (single call on click)
  # ------------------------------------------------------------
  def refund
    pi_id = params[:id]

    acct =
      if current_user.role == "admin"
        acct_param = params[:stripe_account].to_s
        unless acct_param.present? && User.exists?(stripe_user_id: acct_param)
          raise ActionController::BadRequest, "Invalid connected account"
        end
        acct_param
      else
        current_user.stripe_user_id.presence || (raise "Connected Stripe account missing")
      end

    pi = Stripe::PaymentIntent.retrieve(
      { id: pi_id, expand: ["latest_charge"] },
      { stripe_account: acct }
    )

    unless pi.status == "succeeded"
      redirect_back fallback_location: connected_payments_path(status: params[:status], page: params[:page], limit: params[:limit]),
                    alert: "Only succeeded transactions can be refunded."
      return
    end

    ch = pi.latest_charge
    unless ch&.id.present?
      redirect_back fallback_location: connected_payments_path(status: params[:status], page: params[:page], limit: params[:limit]),
                    alert: "Charge not found for this transaction."
      return
    end

    if ch.refunded || ch.amount_refunded.to_i >= ch.amount.to_i
      redirect_back fallback_location: connected_payments_path(status: params[:status], page: params[:page], limit: params[:limit]),
                    notice: "This transaction is already fully refunded."
      return
    end

    refund_params = { charge: ch.id }

    # Refund your platform application fee only if it exists
    if ch.respond_to?(:application_fee) && ch.application_fee.present?
      refund_params[:refund_application_fee] = true
    end

    # Reverse transfer only if it exists
    if ch.respond_to?(:transfer) && ch.transfer.present?
      refund_params[:reverse_transfer] = true
    end

    Stripe::Refund.create(
      refund_params,
      {
        stripe_account: acct,
        idempotency_key: "refund_full_#{acct}_#{ch.id}"
      }
    )

    # Optional: optimistic local update (webhook will also update)
    ConnectedTransaction.where(payment_intent_id: pi.id).update_all(
      refunded: true,
      updated_at: Time.current
    )

    redirect_to connected_payments_path(status: params[:status], page: params[:page], limit: params[:limit]),
                notice: "Refund initiated successfully."

  rescue ActionController::BadRequest => e
    redirect_to connected_payments_path(status: params[:status], page: params[:page], limit: params[:limit]),
                alert: e.message
  rescue Stripe::StripeError => e
    redirect_to connected_payments_path(status: params[:status], page: params[:page], limit: params[:limit]),
                alert: "Stripe error: #{e.message}"
  rescue => e
    redirect_to connected_payments_path(status: params[:status], page: params[:page], limit: params[:limit]),
                alert: "Refund failed: #{e.message}"
  end

  private

  # ------------------------------------------------------------
  # Status filter for DB scope
  # ------------------------------------------------------------
  def apply_status_filter(scope, status)
    return scope if status == "all"

    case status
    when "succeeded"
      scope.where(status: "succeeded")
    when "failed"
      scope.where(status: ["canceled", "requires_payment_method"])
    when "processing"
      scope.where(status: "processing")
    when "requires_action"
      scope.where(status: "requires_action")
    when "canceled"
      scope.where(status: "canceled")
    else
      scope
    end
  end

  # ------------------------------------------------------------
  # Normalize DB row into the same shape your ERB expects
  # ------------------------------------------------------------
  def normalize_tx_row(t)
    {
      id: t.payment_intent_id,
      amount: t.amount,
      currency: (t.currency.presence || "USD"),
      status: t.status,
      payment_method: (t.payment_method_label.presence || "-"),
      description: "-", # add column + webhook if you want this populated
      customer: (t.customer_email.presence || "-"),
      created: t.created_at_stripe,
      created_at: Time.at(t.created_at_stripe).strftime("%b %d, %Y %I:%M %p"),
      stripe_account: t.stripe_account_id,
      charge_id: t.charge_id,
      refunded: t.refunded,
      amount_refunded: t.amount_refunded
    }
  end
end
