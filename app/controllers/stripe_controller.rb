class StripeController < ApplicationController
  before_action :authenticate_user! , only: [:connect]
  require "stripe"
  require 'httparty'
  Stripe.api_key = ENV["STRIPE_SECRET_KEY"]

    def new
    end

    def connect
      response = HTTParty.post("https://connect.stripe.com/oauth/token",
        query: {
          client_secret: ENV["STRIPE_SECRET_KEY"],
          code: params[:code],
          grant_type: "authorization_code",
        }
      )
      if response.parsed_response.key?("error")
        flash[:error] = response.parsed_response["error_description"]
        redirect_to root_path
      else
        stripe_user_id = response.parsed_response["stripe_user_id"]
        current_user.update(stripe_user_id: stripe_user_id)
        begin
          account = Stripe::Account.retrieve(stripe_user_id)
          account.capabilities['transfers'] == 'active' ? current_user.update(transfer: true) : current_user.update(transfer: false)
          current_user.update(payout: account['payouts_enabled'])
          current_user.update(charges: account['charges_enabled'])
          current_user.update(stripe_email: account["email"])
        rescue Stripe::StripeError => e
          flash[:alert] = "Error fetching account information: #{e.message}"
        end
        flash[:success] = "Connected Account Created " +  stripe_user_id
        redirect_to root_path
      end
    end
end
