module ApplicationHelper

  Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
  require "stripe"

  def last_successful_payment_intent(customer_id, connected_account_id)
    intents = Stripe::PaymentIntent.list(
      {
        customer: customer_id,
        limit: 10 # small buffer, in case some are not succeeded
      },
      {
        stripe_account: connected_account_id
      }
    )
    # Pick the most recent with status == 'succeeded'
    intents.data.find { |pi| pi.status == 'succeeded' }
  end

  def format_amount(amount, currency)
    "#{(amount / 100.0).round(2)} #{currency.upcase}"
  end

  def stripe_supported_countries
    [
      ['United States', 'US'],
      ['Canada', 'CA'],
      ['United Kingdom', 'GB'],
      ['Australia', 'AU'],
      ['Austria', 'AT'],
      ['Belgium', 'BE'],
      ['Brazil', 'BR'],
      ['Denmark', 'DK'],
      ['Finland', 'FI'],
      ['France', 'FR'],
      ['Germany', 'DE'],
      ['Hong Kong', 'HK'],
      ['India', 'IN'],
      ['Ireland', 'IE'],
      ['Italy', 'IT'],
      ['Japan', 'JP'],
      ['Luxembourg', 'LU'],
      ['Mexico', 'MX'],
      ['New Zealand', 'NZ'],
      ['Norway', 'NO'],
      ['Portugal', 'PT'],
      ['Singapore', 'SG'],
      ['Spain', 'ES'],
      ['Sweden', 'SE'],
      ['Switzerland', 'CH'],
      ['Netherlands', 'NL'],
      # Add or update according to Stripe docs: https://stripe.com/docs/connect/supported-countries
    ]
  end

  def money_symbols
    {
      'usd' => '$',
      'eur' => '€',
      'gbp' => '£',
      'aed' => 'د.إ'
    }
  end

  def stripe_express_button_link(user)
    @code = rand(8 ** 8)
    user.update(account_type: 'express', role: 'vendor', unique_code: @code)
    begin
      @data = {}
      @data[:individual] = {}
      @data[:individual][:email] = user.email
      @data[:business_type] = "individual"
      connected_account = Stripe::Account.create({
        type: 'express',
        email: user.email,
        country: user.country.present? ? user.country : 'US',
        business_type: @data[:business_type],
        individual: @data[:individual],
        requested_capabilities: ['card_payments', 'transfers']
      })
      user.update(stripe_user_id: connected_account.id)
      account_link = Stripe::AccountLink.create({
        account: connected_account.id,
        refresh_url: authenticated_root_url,  # URL to redirect when the user needs to refresh
        return_url: "#{authenticated_root_url}?id=#{connected_account.id}",
        type: 'account_onboarding',  # Type of link (could also be 'account_update' if updating)
      })

      return account_link.url
    rescue Stripe::StripeError => e
      flash[:alert] = "Error creating Stripe account: #{e.message}"
      return root_path
    end
  end

  def stripe_standard_button_link(user)
    user.update(account_type: 'standard')
    stripe_url = "https://connect.stripe.com/oauth/authorize"
    response_type = "code"
    redirect_uri = stripe_connect_url
    client_id = ENV["STRIPE_CLIENT_ID"]
    scope = "read_write"
  
    return "#{stripe_url}?response_type=#{response_type}&redirect_uri=#{redirect_uri}&client_id=#{client_id}&scope=#{scope}&locale=en"
  end

end