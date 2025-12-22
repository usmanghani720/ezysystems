# app/controllers/customers_controller.rb
class CustomersController < ApplicationController
  Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
  require "stripe"

  def create_payment_form
    @customer = Customer.find(params[:id])
    redirect_to customers_path, alert: "No saved card." and return unless @customer.payment_method.present?
  end

  def create_payment
    @description = params[:description]
    @customer = Customer.find(params[:id])
    amount_cents = (BigDecimal(params[:amount]) * 100).to_i
    connected_acct_id = User.find(@customer.user_id).try(:stripe_user_id)

    if params[:authorize_only].present?
      # --- AUTHORIZE ONLY (manual capture) ---
      res = Payments::OffSessionAuthorize.call(
        customer_id:       @customer.customer_id,
        payment_method_id: @customer.payment_method,
        amount_cents:      amount_cents,
        currency:          "usd",
        idempotency_key:   "auth-#{@customer.id}-#{SecureRandom.uuid}",
        stripe_account:    connected_acct_id,
        description:       @description.blank? ? "Authorization for Customer ##{@customer.id}" : @description,
        force_3ds:         params[:force_3ds].present? ? params[:force_3ds] : nil,
        shipping_name:     params[:shipping_name],
        shipping_line1:    params[:shipping_line1],
        shipping_city:     params[:shipping_city],
        shipping_state:    params[:shipping_state],
        shipping_postal_code: params[:shipping_postal_code],
        shipping_country:  params[:shipping_country]
      )

      case res.status
      when "requires_capture"
        # Store the PI id somewhere you can retrieve to capture later (e.g., on an Order/Payment model).
        # For demo: show a page with a Capture button.
        redirect_to capture_ui_path(pi_id: res.payment_intent_id, customer_id: @customer.id), notice: "Authorized. Awaiting capture."
      when "requires_action"
        @auth_url = authenticate_payment_url(client_secret: res.client_secret, acct: connected_acct_id)
        render "payments/needs_auth"
      else # failed
        redirect_to create_payment_form_path(@customer), alert: res.message || "Authorization failed."
      end
    else
      # --- INSTANT CHARGE (automatic capture) ---
      res = Payments::OffSessionAuthorize.call(
        customer_id:       @customer.customer_id,
        payment_method_id: @customer.payment_method,
        amount_cents:      amount_cents,
        currency:          "usd",
        idempotency_key:   "charge-#{@customer.id}-#{SecureRandom.uuid}",
        stripe_account:    connected_acct_id,
        description:       @description.blank? ? "Manual charge for Customer ##{@customer.id}" : @description,
        shipping_name:     params[:shipping_name],
        shipping_line1:    params[:shipping_line1],
        shipping_city:     params[:shipping_city],
        shipping_state:    params[:shipping_state],
        shipping_postal_code: params[:shipping_postal_code],
        shipping_country:  params[:shipping_country]
      )

      case res.status
      when "succeeded"        then redirect_to customers_path, notice: "Charged successfully."
      when "requires_action"  then @auth_url = authenticate_payment_url(client_secret: res.client_secret, acct: connected_acct_id); render "payments/needs_auth"
      when "requires_capture"  then redirect_to capture_ui_path(pi_id: res.payment_intent_id, customer_id: @customer.id), notice: "Authorized. Awaiting capture."
      else                        redirect_to new_payment_method_path(customer_id: @customer.id), alert: "Payment failed. Ask customer to add a new card."
      end
    end
  rescue => e
    redirect_to create_payment_form_path(@customer), alert: e.message
  end
end
