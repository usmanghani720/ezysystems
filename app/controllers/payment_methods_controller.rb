class PaymentMethodsController < ApplicationController
  require "stripe"
  Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
  
    def new
      @customer = Customer.find_by(id: params[:customer_id])
      if @customer.present? && cookies[:transaction_type] == "customer"
        connected_acct_id = User.find(@customer.user_id).try(:stripe_user_id)
    
        session = Stripe::Checkout::Session.create(
          {
            mode: "setup",
            customer: @customer.customer_id,
            payment_method_types: ["card"],
            currency: ENV["CURRENCY"],
            success_url: payment_method_success_url + "?session_id={CHECKOUT_SESSION_ID}&customer_id=#{@customer.id}",
            cancel_url:  customers_url
          },
          { stripe_account: connected_acct_id }
        )
        @customer.update(customer_card_url: session.url)
        redirect_to session.url, allow_other_host: true
      else  
        @user = User.find_by(id: params[:customer_id])
        session = Stripe::Checkout::Session.create(
          {
            mode: "setup",
            customer: @user.try(:vendor_id),
            payment_method_types: ["card"],
            currency: ENV["CURRENCY"],
            success_url: ENV["SUCCESS_URL"] + "?session_id={CHECKOUT_SESSION_ID}&vendor_id=#{@user.try(:id)}",
            cancel_url:  ENV["CANCEL_URL"]  + "?session_id={CHECKOUT_SESSION_ID}",
          }
        )
        redirect_to session.url, allow_other_host: true
      end
    end
  
    def success
      @customer = Customer.find_by(id: params[:customer_id])
      if @customer.present? && cookies[:transaction_type] == "customer"
        connected_acct_id = User.find(@customer.user_id).try(:stripe_user_id)
        begin
          cs = Stripe::Checkout::Session.retrieve(params[:session_id], { stripe_account: connected_acct_id })
          if cs.setup_intent.present?
            si    = Stripe::SetupIntent.retrieve(cs.setup_intent, { stripe_account: connected_acct_id })
            pm_id = si.payment_method
      
            if pm_id.present?
              @customer.update!(payment_method: pm_id)
              Stripe::Customer.update(
                @customer.customer_id,
                { invoice_settings: { default_payment_method: pm_id } },
                { stripe_account: connected_acct_id }
              )
            end
          end
          @customer.update(customer_card_url: nil)
          redirect_to customers_path, notice: "Card updated."
        rescue => e
          redirect_to customers_path, alert: e.message
        end
      end
    end
  end
  