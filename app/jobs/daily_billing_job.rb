class DailyBillingJob < ApplicationJob
    queue_as :default
    Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
    require 'date'
    include ApplicationHelper

    def perform
      today = Time.now.to_date
      # User.where.not(stripe_user_id: nil).each do |user|
      #   if today.day == 1 || user.try(:monthly_charged).blank?
      #     if user.try(:monthly_charged).blank?
      #       begin
      #         charge = Stripe::Charge.create(
      #           {
      #             amount: 9900,
      #             currency: ENV["CURRENCY"],
      #             source: user.try(:stripe_user_id)
      #           },
      #         )
      #         user.update(monthly_charged: true)
      #       rescue Stripe::CardError => e
      #         puts e.message
      #       rescue Stripe::InvalidRequestError => e
      #         puts e.message
      #       rescue Stripe::RateLimitError => e
      #         puts e.message
      #       rescue Stripe::AuthenticationError => e
      #         puts e.message
      #       rescue Stripe::APIConnectionError => e
      #         puts e.message
      #       rescue Stripe::StripeError => e
      #         puts e.message
      #       rescue => e
      #         puts "System Error"
      #       end
      #     elsif today.day == 1 
      #       user.update(monthly_charged: nil)
      #       begin
      #         charge = Stripe::Charge.create(
      #           {
      #             amount: 9900,
      #             currency: ENV["CURRENCY"],
      #             source: user.try(:stripe_user_id)
      #           },
      #         )
      #         user.update(monthly_charged: true)
      #       rescue Stripe::CardError => e
      #         puts e.message
      #       rescue Stripe::InvalidRequestError => e
      #         puts e.message
      #       rescue Stripe::RateLimitError => e
      #         puts e.message
      #       rescue Stripe::AuthenticationError => e
      #         puts e.message
      #       rescue Stripe::APIConnectionError => e
      #         puts e.message
      #       rescue Stripe::StripeError => e
      #         puts e.message
      #       rescue => e
      #         puts "System Error"
      #       end
      #     end
      #   end
      # end

      begin
        @accounts = Stripe::Account.list({limit: 200})
        User.all.each do |user|
          if user.stripe_user_id.present?
            begin
              @account = Stripe::Account.retrieve(user.stripe_user_id)
              user.update(payout: @account['payouts_enabled'])
              user.update(charges: @account['charges_enabled'])
              @account.capabilities['transfers'] == 'active' ? user.update(transfer: true) : user.update(transfer: false)
            rescue Stripe::CardError => e
              puts e.message
            rescue Stripe::InvalidRequestError => e
              puts e.message
            rescue Stripe::RateLimitError => e
              puts e.message
            rescue Stripe::AuthenticationError => e
              puts e.message
            rescue Stripe::APIConnectionError => e
              puts e.message
            rescue Stripe::StripeError => e
              puts e.message
            rescue => e
              puts "System Error"
            end
          end
        end
      rescue Stripe::CardError => e
        puts e.message
      rescue Stripe::InvalidRequestError => e
        puts e.message
      rescue Stripe::RateLimitError => e
        puts e.message
      rescue Stripe::AuthenticationError => e
        puts e.message
      rescue Stripe::APIConnectionError => e
        puts e.message
      rescue Stripe::StripeError => e
        puts e.message
      rescue => e
        puts "System Error"
      end

      Customer.where.not(payment_method: nil).each do |customer|
        begin
          connected_acct_id = User.find(customer.user_id).try(:stripe_user_id)
          pi = last_successful_payment_intent(customer.customer_id, connected_acct_id)
          if pi.present?
            customer.update(last_payment_id: pi["id"], last_payment_amount: pi["amount"]/100, last_payment_currency: pi["currency"], last_payment_date: Time.at(pi["created"]).to_date)
          end
        rescue => e
          puts "System Error"
        end
      end
    end
  end