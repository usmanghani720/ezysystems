class DailyBillingJob < ApplicationJob
    queue_as :default
    Stripe.api_key = ENV["STRIPE_SECRET_KEY"]

    def perform
      begin
        @accounts = Stripe::Account.list({limit: 200})
        User.all.each do |user|
          if user.stripe_user_id.present?
            begin
              @account = Stripe::Account.retrieve(user.stripe_user_id)
              user.update(payout: @account['payouts_enabled'])
              user.update(charges: @account['charges_enabled'])
              @account.capabilities['transfers'] == 'active' ? user.update(transfer: true) : user.update(transfer: false)
              # if !@account['charges_enabled'] && !@account['payouts_enabled'] && (@account.capabilities['transfers'] == "inactive" || @account.capabilities['transfers'].nil?)
              #   begin
              #     account_link = Stripe::AccountLink.create({
              #       account: user.stripe_user_id,
              #       refresh_url: "https://factuur.appointmentssetter.nl",  # URL to redirect when the user needs to refresh
              #       return_url: "#{"https://factuur.appointmentssetter.nl/"}?id=#{user.stripe_user_id}",
              #       type: 'account_onboarding',  # Type of link (could also be 'account_update' if updating)
              #     })
              #     @onboarding_url = account_link["url"]
              #     UserMailer.send_onboarding_url(@account["email"], @onboarding_url).deliver_now()
              #   rescue Stripe::CardError => e
              #     puts e.message
              #   rescue Stripe::InvalidRequestError => e
              #     puts e.message
              #   rescue Stripe::RateLimitError => e
              #     puts e.message
              #   rescue Stripe::AuthenticationError => e
              #     puts e.message
              #   rescue Stripe::APIConnectionError => e
              #     puts e.message
              #   rescue Stripe::StripeError => e
              #     puts e.message
              #   rescue => e
              #     puts "Error"
              #   end
              # end
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