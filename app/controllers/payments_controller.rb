class PaymentsController < ApplicationController
  Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
  require "stripe"
  include ApplicationHelper
  before_action :authenticate_user!, except: [:success, :cancel]
  before_action :validate_admin_user! , only: [:all_users, :update_user_status]
  Stripe.api_key = ENV["STRIPE_SECRET_KEY"]

  def new
    if current_user.role == "admin"
      redirect_to users_path
    end
    if current_user.role != "admin"
      begin
        account = Stripe::Account.retrieve(params[:id])
        @individual_details = account.individual || {}
        @company_details = account.company || {}
        account.capabilities['transfers'] == 'active' ? current_user.update(transfer: true) : current_user.update(transfer: false)
        current_user.update(payout: account['payouts_enabled'])
        current_user.update(charges: account['charges_enabled'])
        current_user.update(stripe_email: account["email"])
      rescue Stripe::StripeError => e
        flash[:alert] = "Error fetching account information: #{e.message}"
      end
    end
    if current_user.stripe_user_id.present? && current_user.account_type == "express"
      @restricted = false
      begin
        @login_link = Stripe::Account.create_login_link(current_user.stripe_user_id)
      rescue Stripe::CardError => e
        flash[:error] = e.message
        @restricted = true
      rescue Stripe::InvalidRequestError => e
        flash[:error] = e.message
        @restricted = true
      rescue Stripe::RateLimitError => e
        flash[:error] = e.message
        @restricted = true
      rescue Stripe::AuthenticationError => e
        flash[:error] = e.message
        @restricted = true
      rescue Stripe::APIConnectionError => e
        flash[:error] = e.message
        @restricted = true
      rescue Stripe::StripeError => e
        flash[:error] = e.message
        @restricted = true
      rescue => e
        flash[:error] = "System Error"
        @restricted = true
      end
      if @restricted == true
        begin
          account_link = Stripe::AccountLink.create({
            account: current_user.stripe_user_id,
            refresh_url: Rails.env.development? ? "http://localhost:3000" : "https://factuur.appointmentssetter.nl",
            return_url: Rails.env.development? ? "#{"http://localhost:3000"}?id=#{current_user.stripe_user_id}" : "#{"https://factuur.appointmentssetter.nl"}?id=#{current_user.stripe_user_id}",
            type: 'account_onboarding',
          })
          @onboarding_url = account_link["url"]
        rescue Stripe::CardError => e
          flash[:error] = e.message
        rescue Stripe::InvalidRequestError => e
          flash[:error] = e.message
        rescue Stripe::RateLimitError => e
          flash[:error] = e.message
        rescue Stripe::AuthenticationError => e
          flash[:error] = e.message
        rescue Stripe::APIConnectionError => e
          flash[:error] = e.message
        rescue Stripe::StripeError => e
          flash[:error] = e.message
        rescue => e
          flash[:error] = "System Error"
        end
      end
    end
    if current_user.stripe_user_id.present?
      @account = Stripe::Account.retrieve(current_user.stripe_user_id)
      @individual_details = @account["individual"] || {}
      @company_details = @account["company"] || {}
    end
  end

  def capture_ui
    @pi_id      = params[:pi_id]
    @customer   = Customer.find(params[:customer_id])
    @acct_id    = User.find(@customer.user_id).try(:stripe_user_id)
    # Fetch latest PI to show amount_capturable
    @pi = Stripe::PaymentIntent.retrieve(@pi_id, { stripe_account: @acct_id })
  end

  def capture
    customer   = Customer.find(params[:customer_id])
    acct_id    = User.find(customer.user_id).try(:stripe_user_id)
    pi_id      = params[:pi_id]
    amount_cents = params[:amount].present? ? (BigDecimal(params[:amount]) * 100).to_i : nil

    res = Payments::CapturePaymentIntent.call(
      payment_intent_id: pi_id,
      stripe_account:    acct_id,
      idempotency_key:   "capture-#{pi_id}-#{SecureRandom.uuid}",
      amount_to_capture_cents: amount_cents # nil => full amount
    )

    if res.ok
      redirect_to customers_path, notice: "Capture submitted. Status: #{res.status}."
    else
      redirect_to capture_ui_path(pi_id: pi_id, customer_id: customer.id), alert: res.message || "Capture failed."
    end
  end

  def authenticate
    @client_secret = params[:client_secret]
    @acct          = params[:acct] # optional, if you want to display which account
  end

  def create_express_account
    account_link = stripe_express_button_link(current_user)
    redirect_to account_link
  end

  def create_standard_account
    account_link = stripe_standard_button_link(current_user)
    redirect_to account_link
  end

  def update_user_status
    @user = User.find_by(id: params[:id])
    if @user.present?
      if @user.approved 
        @user.update(approved: nil)
        UserMailer.send_disapprove_email_to_vendor(@user).deliver_now
      else  
        @user.update(approved: true)
        UserMailer.send_approve_email_to_vendor(@user).deliver_now
      end
    end
  end

  def customers
    @customers = Customer.where(user_id: current_user.try(:id))
  end

  def new_customer

  end  

  def create_payment

  end

  def new_payment_link

  end

  def create_custom_payment_link 
    begin
      amount_cents = (params[:amount].to_f * 100 ).to_i
      percentage = params[:percentage].present? ? params[:percentage] : 10
      platform_fee_cents = (percentage.to_i * params[:amount].to_f).to_i     
      connected_account_id = current_user.try(:stripe_user_id)
      session = Stripe::Checkout::Session.create({
        payment_method_types: ['card'],
        line_items: [{
          price_data: {
            currency: ENV["CURRENCY"],
            unit_amount: amount_cents,
            product_data: {
              name: params[:name],
              description: params[:description].present? ? params[:description] : params[:name]
            },
          },
          quantity: 1,
        }],
        mode: 'payment',
        success_url: ENV['SUCCESS_URL'] + "?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: ENV['CANCEL_URL'] + "?session_id={CHECKOUT_SESSION_ID}",
        payment_intent_data: {
          on_behalf_of: connected_account_id, # Ensures the connected account is the merchant of record
          application_fee_amount: platform_fee_cents, # 10% fee to the platform
          transfer_data: {
            destination: connected_account_id, # Connected account receives the remaining balance
          },
        },
      })
      redirect_to session.url, allow_other_host: true
      
    rescue Stripe::CardError => e
      flash[:error] = e.message
      redirect_to authenticated_root_path
    rescue Stripe::InvalidRequestError => e
      flash[:error] = e.message
      redirect_to authenticated_root_path
    rescue Stripe::RateLimitError => e
      flash[:error] = e.message
      redirect_to authenticated_root_path
    rescue Stripe::AuthenticationError => e
      flash[:error] = e.message
      redirect_to authenticated_root_path
    rescue Stripe::APIConnectionError => e
      flash[:error] = e.message
      redirect_to authenticated_root_path
    rescue Stripe::StripeError => e
      flash[:error] = e.message
      redirect_to authenticated_root_path
    rescue => e
      flash[:error] = "System Error"
      redirect_to authenticated_root_path
    end 
  end

  def remove_customer
    @customer = Customer.find_by(id: params[:format])
    if @customer.present? 
      connected_acct_id = User.find(@customer.user_id).try(:stripe_user_id)
      customer_id = @customer.try(:customer_id)
      begin
        Stripe::Customer.delete(customer_id, {}, { stripe_account: connected_acct_id})
        @customer.delete
        redirect_to customers_path
      rescue Stripe::CardError => e
        flash[:error] = e.message
        redirect_to customers_path
      rescue Stripe::InvalidRequestError => e
        flash[:error] = e.message
        redirect_to customers_path
      rescue Stripe::RateLimitError => e
        flash[:error] = e.message
        redirect_to customers_path
      rescue Stripe::AuthenticationError => e
        flash[:error] = e.message
        redirect_to customers_path
      rescue Stripe::APIConnectionError => e
        flash[:error] = e.message
        redirect_to customers_path
      rescue Stripe::StripeError => e
        flash[:error] = e.message
        redirect_to customers_path
      rescue => e
        flash[:error] = "System Error"
        redirect_to customers_path
      end
    end
  end

  def customer_creation_success
    @customer = Customer.find(params[:id])
    connected_acct_id = User.find(@customer.user_id).try(:stripe_user_id)

    @stripe_customer = Stripe::Customer.retrieve(@customer.customer_id,{stripe_account: connected_acct_id})

  
    begin
      # 1) Get the Checkout Session that just finished
      checkout_session = Stripe::Checkout::Session.retrieve(
        params[:session_id],
        { stripe_account: connected_acct_id }
      )
  
      # 2) It will have a setup_intent; fetch it
      if checkout_session.setup_intent.present?
        si = Stripe::SetupIntent.retrieve(
          checkout_session.setup_intent,
          { stripe_account: connected_acct_id }
        )
  
        # 3) Pull the exact payment method saved during Checkout
        pm_id = si.payment_method
        if pm_id.present?
          # 4) Save it locally and make it default for the customer
          @customer.update!(payment_method: pm_id)
          pm = Stripe::PaymentMethod.retrieve(pm_id, {stripe_account: connected_acct_id})
          if pm.present? && pm["card"].present?
            @customer.update(last4: pm["card"]["last4"], brand: pm["card"]["brand"])
          end
          Stripe::Customer.update(
            @customer.customer_id,
            { invoice_settings: { default_payment_method: pm_id } },
            { stripe_account: connected_acct_id }
          )
        end
      end
      @customer.update(customer_card_url: nil)
      redirect_to success_path
    rescue => e
      flash[:error] = e.message.presence || "System Error"
      redirect_to cancel_path
    end
  end

  def make_payment
    @customer = Customer.find_by(id: params[:id])
    connected_acct_id = User.find_by(id: @customer.try(:user_id)).try(:stripe_user_id)
    begin
      customer = Stripe::Customer.retrieve(
        @customer.customer_id,
        { stripe_account: connected_acct_id } # opts: target the connected account
      )
    rescue Stripe::CardError => e
      flash[:error] = e.message
      redirect_to customers_path
    rescue Stripe::InvalidRequestError => e
      flash[:error] = e.message
      redirect_to customers_path
    rescue Stripe::RateLimitError => e
      flash[:error] = e.message
      redirect_to customers_path
    rescue Stripe::AuthenticationError => e
      flash[:error] = e.message
      redirect_to customers_path
    rescue Stripe::APIConnectionError => e
      flash[:error] = e.message
      redirect_to customers_path
    rescue Stripe::StripeError => e
      flash[:error] = e.message
      redirect_to customers_path
    rescue => e
      flash[:error] = "System Error"
      redirect_to customers_path
    end
    if @customer.payment_method.blank?
      begin
        cards = Stripe::PaymentMethod.list(
          { customer: @customer.customer_id, type: "card" },
          { stripe_account: connected_acct_id }
        ).data
        if cards.present?
          @customer.update(payment_method: cards.first["id"])
          Stripe::Customer.update(
            @customer.customer_id,
            { invoice_settings: { default_payment_method: cards.first["id"] } },
            { stripe_account: connected_acct_id }
          )
          @payment_method = cards.first["id"]  
        else    
        end
      rescue Stripe::CardError => e
        flash[:error] = e.message
        redirect_to customers_path
      rescue Stripe::InvalidRequestError => e
        flash[:error] = e.message
        redirect_to customers_path
      rescue Stripe::RateLimitError => e
        flash[:error] = e.message
        redirect_to customers_path
      rescue Stripe::AuthenticationError => e
        flash[:error] = e.message
        redirect_to customers_path
      rescue Stripe::APIConnectionError => e
        flash[:error] = e.message
        redirect_to customers_path
      rescue Stripe::StripeError => e
        flash[:error] = e.message
        redirect_to customers_path
      rescue => e
        flash[:error] = "System Error"
        redirect_to customers_path
      end
    else   
      @payment_method = @customer.payment_method
    end
      begin
        pi = Stripe::PaymentIntent.create(
          {
            amount: ((params[:amount].to_f) * 100).to_i,
            currency: "usd",
            customer: @customer.customer_id,   # Customer that exists on the CONNECTED account
            payment_method: @customer.payment_method,           # their saved PM on connected
            confirm: true,
            off_session: true,
          },
          { stripe_account: connected_acct_id } # ← key line for direct charges
        )
        flash[:success] = "Payment Successful"
      rescue Stripe::CardError => e
        flash[:error] = e.message
        redirect_to customers_path
      rescue Stripe::InvalidRequestError => e
        flash[:error] = e.message
        redirect_to customers_path
      rescue Stripe::RateLimitError => e
        flash[:error] = e.message
        redirect_to customers_path
      rescue Stripe::AuthenticationError => e
        flash[:error] = e.message
        redirect_to customers_path
      rescue Stripe::APIConnectionError => e
        flash[:error] = e.message
        redirect_to customers_path
      rescue Stripe::StripeError => e
        flash[:error] = e.message
        redirect_to customers_path
      rescue => e
        flash[:error] = "System Error"
        redirect_to customers_path
      end
      redirect_to customers_path
  end

  def create_customer
    @customer = Customer.create(email: params[:email], 
      name: params[:name], 
      phone: params[:phone], 
      line1: params[:line1], 
      line2: params[:line2], 
      city: params[:city], 
      state: params[:state], 
      postal_code: params[:postal_code], 
      country: params[:country], 
      user_id: current_user.try(:id))
    begin  
      customer = Stripe::Customer.create(
        {
          name:  params[:name],
          email: params[:email],
          phone: params[:phone],
          address: {
            line1:       params[:line1].presence,
            line2:       params[:line2].presence,
            city:        params[:city].presence,
            state:       params[:state].presence,
            postal_code: params[:postal_code].presence,
            country:     params[:country].presence
          },
          shipping: {
            phone: params[:phone],
            name: params[:name],
          address: {
            line1:       params[:line1].presence,
            line2:       params[:line2].presence,
            city:        params[:city].presence,
            state:       params[:state].presence,
            postal_code: params[:postal_code].presence,
            country:     params[:country].presence,
          },
          }
        },
        { stripe_account: current_user.try(:stripe_user_id) }
      )
      @customer.update(customer_id: customer["id"])
    rescue Stripe::CardError => e
      puts "***************"
      puts e.message
      puts "***************"
      flash[:error] = e.message
    rescue Stripe::InvalidRequestError => e
      puts "***************"
      puts e.message
      puts "***************"
      flash[:error] = e.message
    rescue Stripe::RateLimitError => e
      puts "***************"
      puts e.message
      puts "***************"
      flash[:error] = e.message
    rescue Stripe::AuthenticationError => e
      puts "***************"
      puts e.message
      puts "***************"
      flash[:error] = e.message
    rescue Stripe::APIConnectionError => e
      puts "***************"
      puts e.message
      puts "***************"
      flash[:error] = e.message
    rescue Stripe::StripeError => e
      puts "***************"
      puts e.message
      puts "***************"
      flash[:error] = e.message
    rescue => e
      flash[:error] = "System Error"
    end
    flash[:success] = "Customer created"
    if @customer.present?
      connected_acct_id = User.find_by(id: @customer.try(:user_id)).try(:stripe_user_id)
      customer_id = @customer.customer_id
    end

    session = Stripe::Checkout::Session.create(
      {
        mode: "setup",
        customer: customer_id,
        payment_method_types: ["card"],
        shipping_address_collection: {
          allowed_countries: ["AC", "AD", "AE", "AF", "AG", "AI", "AL", "AM", "AO", "AQ", "AR", "AT", "AU", "AW", "AX", "AZ", "BA", "BB", "BD", "BE", "BF", "BG", "BH", "BI", "BJ", "BL", "BM", "BN", "BO", "BQ", "BR", "BS", "BT", "BV", "BW", "BY", "BZ", "CA", "CD", "CF", "CG", "CH", "CI", "CK", "CL", "CM", "CN", "CO", "CR", "CV", "CW", "CY", "CZ", "DE", "DJ", "DK", "DM", "DO", "DZ", "EC", "EE", "EG", "EH", "ER", "ES", "ET", "FI", "FJ", "FK", "FO", "FR", "GA", "GB", "GD", "GE", "GF", "GG", "GH", "GI", "GL", "GM", "GN", "GP", "GQ", "GR", "GS", "GT", "GU", "GW", "GY", "HK", "HN", "HR", "HT", "HU", "ID", "IE", "IL", "IM", "IN", "IO", "IQ", "IS", "IT", "JE", "JM", "JO", "JP", "KE", "KG", "KH", "KI", "KM", "KN", "KR", "KW", "KY", "KZ", "LA", "LB", "LC", "LI", "LK", "LR", "LS", "LT", "LU", "LV", "LY", "MA", "MC", "MD", "ME", "MF", "MG", "MK", "ML", "MM", "MN", "MO", "MQ", "MR", "MS", "MT", "MU", "MV", "MW", "MX", "MY", "MZ", "NA", "NC", "NE", "NG", "NI", "NL", "NO", "NP", "NR", "NU", "NZ", "OM", "PA", "PE", "PF", "PG", "PH", "PK", "PL", "PM", "PN", "PR", "PS", "PT", "PY", "QA", "RE", "RO", "RS", "RU", "RW", "SA", "SB", "SC", "SD", "SE", "SG", "SH", "SI", "SJ", "SK", "SL", "SM", "SN", "SO", "SR", "SS", "ST", "SV", "SX", "SZ", "TA", "TC", "TD", "TF", "TG", "TH", "TJ", "TK", "TL", "TM", "TN", "TO", "TR", "TT", "TV", "TW", "TZ", "UA", "UG", "US", "UY", "UZ", "VA", "VC", "VE", "VG", "VN", "VU", "WF", "WS", "XK", "YE", "YT", "ZA", "ZM", "ZW", "ZZ"],
        },
        success_url: ENV['CUSTOMER_CREATION_SUCCESS'] + "?session_id={CHECKOUT_SESSION_ID}&id=#{@customer.try(:id)}",
        cancel_url: ENV['CANCEL_URL'] + "?session_id={CHECKOUT_SESSION_ID}&id=#{@customer.try(:id)}",
      },
      { stripe_account: connected_acct_id }
    )
    cookies[:session_url] = session.url
    @customer.update(customer_card_url: session.url)
    redirect_to success_path
  end

  def all_users
    @users = User.all
  end

  def invoice
  end

  def create_payment_link
    amount = (params[:amount].to_i * 100)
    email = params[:email]
    @unique_id = SecureRandom.hex(6).upcase
    @invoice = Invoice.create(unique_id: @unique_id, email: email, name: params[:name], description: params[:description], amount: amount, currency: "usd", user_id: current_user.try(:id))
    begin
      session = Stripe::Checkout::Session.create({
        payment_method_types: ['card'],
        line_items: [{
          price_data: {
            currency: "usd",
            unit_amount: amount,
            product_data: {
              name: params[:name],
              description: params[:description]
            },
          },
          quantity: 1,
        }],
        mode: 'payment',
        success_url: ENV['SUCCESS_URL'] + "?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: ENV['CANCEL_URL'] + "?session_id={CHECKOUT_SESSION_ID}",
        payment_intent_data: {
          on_behalf_of: current_user.try(:stripe_user_id), # Ensures the connected account is the merchant of record
          application_fee_amount: 0,
          transfer_data: {
            destination: current_user.try(:stripe_user_id), # Connected account receives the remaining balance
          },
        },
      })

      @invoice.update(invoice_url: session.url)
      flash[:success] = "Invoice sent to customer"

    rescue Stripe::CardError => e
      if @invoice.present?
        @invoice.delete
      end
      flash[:error] = e.message
      redirect_to authenticated_root_path
    rescue Stripe::InvalidRequestError => e
      if @invoice.present?
        @invoice.delete
      end
      flash[:error] = e.message
      redirect_to authenticated_root_path
    rescue Stripe::RateLimitError => e
      if @invoice.present?
        @invoice.delete
      end
      flash[:error] = e.message
      redirect_to authenticated_root_path
    rescue Stripe::AuthenticationError => e
      if @invoice.present?
        @invoice.delete
      end
      flash[:error] = e.message
      redirect_to authenticated_root_path
    rescue Stripe::APIConnectionError => e
      if @invoice.present?
        @invoice.delete
      end
      flash[:error] = e.message
      redirect_to authenticated_root_path
    rescue Stripe::StripeError => e
      if @invoice.present?
        @invoice.delete
      end
      flash[:error] = e.message
      redirect_to authenticated_root_path
    rescue => e
      if @invoice.present?
        @invoice.delete
      end
      flash[:error] = "System Error"
      redirect_to authenticated_root_path
    end
    UserMailer.send_payment_link(@invoice).deliver_now
    redirect_to authenticated_root_path
  end

  def success
    if cookies[:session_url].present? 
      @session_url = cookies[:session_url]
      cookies.delete :session_url
    end
  end

  def cancel 

  end

  def invoices
    if current_user.try(:role) == "admin"
      @invoices = Invoice.all.order('created_at desc')
    else
      @invoices = Invoice.where(user_id: current_user.try(:id)).order('created_at desc')
    end
  end

  def payouts
    @payouts = Payout.where(user_id: current_user.try(:id)).order('created_at desc')
    begin
      # Retrieve the current balance from Stripe
      balance = Stripe::Balance.retrieve({}, { stripe_account: current_user.try(:stripe_user_id) })

      # Pass the balance to the view
      @available_balance = balance.available.first.amount / 100.0  # Available balance in the default currency
      @pending_balance = balance.pending.first.amount / 100.0  # Pending balance in the default currency
      @currency = balance.pending.first.currency

    rescue Stripe::StripeError => e
      flash[:alert] = "Error retrieving balance: #{e.message}"
      redirect_to new_payment_path
    end
  end

  def payout

  end

  def create_small_payout
    begin
      balance = Stripe::Balance.retrieve({}, { stripe_account: current_user.try(:stripe_user_id) })
      Stripe::Payout.create({
        amount: (params[:amount].to_i) * 100,
        currency: balance.available.first.currency,
      },
      { stripe_account: current_user.try(:user_id) })
      Payout.create(amount: params[:amount].to_i, user_id: current_user.try(:id))
      flash[:success] = "Payout completed"
    rescue Stripe::CardError => e
      puts "***************"
      puts e.message
      puts "***************"
      flash[:error] = e.message
    rescue Stripe::InvalidRequestError => e
      puts "***************"
      puts e.message
      puts "***************"
      flash[:error] = e.message
    rescue Stripe::RateLimitError => e
      puts "***************"
      puts e.message
      puts "***************"
      flash[:error] = e.message
    rescue Stripe::AuthenticationError => e
      puts "***************"
      puts e.message
      puts "***************"
      flash[:error] = e.message
    rescue Stripe::APIConnectionError => e
      puts "***************"
      puts e.message
      puts "***************"
      flash[:error] = e.message
    rescue Stripe::StripeError => e
      puts "***************"
      puts e.message
      puts "***************"
      flash[:error] = e.message
    rescue => e
      flash[:error] = "System Error"
    end
    redirect_to payouts_path
  end

  def create_payout
      @balance = Stripe::Balance.retrieve({}, { stripe_account: current_user.try(:stripe_user_id) })
      @available_balance = balance.available.first.amount
      if @balance > 0
        begin
          Stripe::Payout.create({
            amount: @available_balance,
            currency: @balance.available.first.currency,
          },
          { stripe_account: current_user.try(:user_id) })
          Payout.create(amount: @balance, user_id: current_user.try(:user_id))
          flash[:success] = "Payout completed"
        rescue Stripe::CardError => e
          puts "***************"
          puts e.message
          puts "***************"
          flash[:error] = e.message
        rescue Stripe::InvalidRequestError => e
          puts "***************"
          puts e.message
          puts "***************"
          flash[:error] = e.message
        rescue Stripe::RateLimitError => e
          puts "***************"
          puts e.message
          puts "***************"
          flash[:error] = e.message
        rescue Stripe::AuthenticationError => e
          puts "***************"
          puts e.message
          puts "***************"
          flash[:error] = e.message
        rescue Stripe::APIConnectionError => e
          puts "***************"
          puts e.message
          puts "***************"
          flash[:error] = e.message
        rescue Stripe::StripeError => e
          puts "***************"
          puts e.message
          puts "***************"
          flash[:error] = e.message
        rescue => e
          flash[:error] = "System Error"
        end
      end
  end

  private
    def validate_admin_user!
      if current_user.nil? || !current_user.admin?
        flash[:alert] = 'Permission Denied! Its only for admin.'
        sign_out(current_user)
        redirect_to root_path
      end
    end

end