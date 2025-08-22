class DailyBillingJob < ApplicationJob
    queue_as :default
    Stripe.api_key = ENV["STRIPE_SECRET_KEY"]

    def perform
      User.where.not(stripe_user_id: nil).each do |user|
        begin
          charge = Stripe::Charge.create(
            {
              amount: 9900,
              currency: ENV["CURRENCY"],
              source: user.try(:stripe_user_id)
            },
          )
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
    end
  end