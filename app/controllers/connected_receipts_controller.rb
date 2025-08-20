class ConnectedReceiptsController < ApplicationController
  require "stripe"
  include ApplicationHelper
  before_action :authenticate_user!
  Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
  
    def show
      @payment_id = params[:id]
      begin
        # Fetch PaymentIntent and related data
        @payment_intent = Stripe::PaymentIntent.retrieve(@payment_id)
        @connected_account_id = current_user.try(:stripe_user_id)
        @connected_account = Stripe::Account.retrieve(@connected_account_id)
        
        # Calculate the amount transferred to the connected account
        @transfer_amount = (@payment_intent.amount - @payment_intent.application_fee_amount) / 100.0
      rescue Stripe::CardError => e
        flash[:error] = e.message
        redirect_to root_path
      rescue Stripe::InvalidRequestError => e
        flash[:error] = e.message
        redirect_to root_path
      rescue Stripe::RateLimitError => e
        flash[:error] = e.message
        redirect_to root_path
      rescue Stripe::AuthenticationError => e
        flash[:error] = e.message
        redirect_to root_path
      rescue Stripe::APIConnectionError => e
        flash[:error] = e.message
        redirect_to root_path
      rescue Stripe::StripeError => e
        flash[:error] = e.message
        redirect_to root_path
      rescue => e
        flash[:error] = "System Error"
        redirect_to root_path
      end
  
      # Render HTML view
      render :show
    end
  
  end