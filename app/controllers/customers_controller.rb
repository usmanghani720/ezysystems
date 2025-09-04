class CustomersController < ApplicationController
    Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
    # GET /create_payment/:id
    def create_payment_form
      @customer = Customer.find(params[:id])
      unless @customer.payment_method.present?
        redirect_to customers_path, alert: "No saved card. Ask customer to add a card first."
        return
      end
    end
  
    # POST /create_payment/:id
    def create_payment
      @customer = Customer.find(params[:id])
      amount_dollars = params[:amount].to_s.strip
      unless amount_dollars.match?(/\A\d+(\.\d{1,2})?\z/)
        redirect_to create_payment_form_path(@customer), alert: "Enter a valid amount."
        return
      end

  
      amount_cents = (BigDecimal(amount_dollars) * 100).to_i
      connected_acct_id = User.find(@customer.user_id).try(:stripe_user_id)
  
      result = Payments::OffSessionCharge.call(
        customer_id:      @customer.customer_id,
        payment_method_id:@customer.payment_method,
        amount_cents:     amount_cents,
        currency:         "usd",
        idempotency_key:  "cust-#{@customer.id}-#{SecureRandom.uuid}",
        stripe_account:   connected_acct_id,
        description:      "Manual charge for Customer ##{@customer.id}"
      )
  
      case result.status
      when "succeeded"
        redirect_to customers_path, notice: "Charged $#{amount_dollars} successfully."
      when "requires_action"
        # Show a page with a shareable link your customer can open to complete 3DS.
        # (You can also email this link to them.)
        @auth_url = authenticate_payment_url(client_secret: result.client_secret, acct: connected_acct_id)
        render "payments/needs_auth"  # simple view below
      else # "failed"
        # If soft decline you MAY schedule one gentle retry (e.g. with a job); otherwise ask for a new card.
        if result.soft_decline
          flash[:alert] = "Payment declined (#{result.decline_code}). Try again later or ask customer to update their card."
        else
          flash[:alert] = "Payment failed (#{result.decline_code || 'hard decline'}). Ask customer to add a new card."
        end
        redirect_to new_payment_method_path(customer_id: @customer.id)
      end
    rescue => e
      redirect_to create_payment_form_path(@customer), alert: e.message
    end
  end
  