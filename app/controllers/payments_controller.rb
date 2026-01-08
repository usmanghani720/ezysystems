class PaymentsController < ApplicationController
  Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
  require "stripe"
  include ApplicationHelper
  before_action :authenticate_user!, except: [:success, :checkout_url, :customer_creation_success, :checkout_url, :stripe_invoice_url]
  before_action :validate_admin_user! , only: [:all_users, :update_user_status, :remove_user]
  before_action :validate_vendor_user!, except: [:new_customer, :success, :cancel, :create_customer, :new, :customer_creation_success, :checkout_url, :stripe_invoice_url, :add_note ]
  Stripe.api_key = ENV["STRIPE_SECRET_KEY"]

  def new
    if current_user.role == "admin"
      redirect_to users_path
    end
    if current_user.role != "customer"
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
            refresh_url: ENV['WEBSITE_URL'],
            return_url: "#{ENV['WEBSITE_URL']}?id=#{current_user.stripe_user_id}",
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
      begin
        @account = Stripe::Account.retrieve(current_user.stripe_user_id)
        @individual_details = @account["individual"] || {}
        @company_details = @account["company"] || {}
      rescue Stripe::StripeError => e
        flash[:alert] = "Error fetching account information: #{e.message}"
      end
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

  def update_user_3d
    @user = User.find_by(id: params[:id])
    if @user.present?
      if @user.require_3ds 
        @user.update(require_3ds: false)
      else  
        @user.update(require_3ds: true)
      end
    end
    if current_user.try(:role) != "admin"
      redirect_to authenticated_root_path
    end
  end

  def set_minimum_balance 
    @user = User.find_by(id: params[:id])
    if @user.try(:stripe_user_id).present?
      begin 
        client = Stripe::StripeClient.new(ENV["STRIPE_SECRET_KEY"])

        client.v1.balance_settings.update(
          {
            payments: {
              payouts: {
                minimum_balance_by_currency: {
                  "usd" => ((params[:amount].to_f * 100).to_i)
                }
              }
            }
          },
          stripe_account: @user.try(:stripe_user_id)
        )
        redirect_to authenticated_root_path
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
    else   
      flash[:error] = "No connected account"
      redirect_to authenticated_root_path
    end
  end

  def customers
    @customers = Customer.where(user_id: current_user.try(:id))
  end

  def new_customer
    if current_user.role == "customer"
      @user = current_user
    end
  end  

  def create_payment
  end

  def new_payment_link
    @customers = Customer.where(user_id: current_user.try(:id)).order(:name)
  end

  def redirect_checkout
    session_id = params[:id]
    raise "no session found" unless session_id
  
    connected_account_id = current_user.stripe_user_id
    begin
      checkout_session = Stripe::Checkout::Session.retrieve(
        session_id,
        { stripe_account: connected_account_id }
      )
    rescue Stripe::StripeError => e
      flash[:alert] = "#{e.message}"
      redirect_to authenticated_root_path
    end
  
    redirect_to checkout_session.url, allow_other_host: true
  end

  def create_saved_card_intent
    customer = Customer.find_by(id: params[:customer_id])
    connected_acct_id = current_user.stripe_user_id
    raise "Connected Stripe account missing" unless connected_acct_id.present?

    stripe_customer_id = customer.customer_id       # cus_...
    pm_id             = customer.payment_method     # pm_... (saved earlier)

    amount_cents = (params[:amount].to_f * 100).round
    percentage   = (params[:percentage].presence || 0).to_f
    fee_cents    = (amount_cents * (percentage / 100.0)).round

    intent = Stripe::PaymentIntent.create(
      {
        amount:   amount_cents,
        currency: ENV["CURRENCY"] || "usd",

        customer:       stripe_customer_id,
        payment_method: pm_id,

        confirmation_method: "automatic",
        confirm:             false,   # will confirm from JS after CVC

        application_fee_amount: fee_cents,

        shipping: {
          name: params[:shipping_name],
          address: {
            line1:       params[:shipping_line1],
            city:        params[:shipping_city],
            state:       params[:shipping_state],
            postal_code: params[:shipping_postal_code],
            country:     params[:shipping_country]
          }
        },
        # Strong hint to Stripe we want CVC when using this saved card
        payment_method_options: {
          card: {
            require_cvc_recollection: true
          }
        }
      },
      { stripe_account: connected_acct_id }
    )

    render json: { client_secret: intent.client_secret }
  rescue Stripe::StripeError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue => e
    render json: { error: "System Error" }, status: :unprocessable_entity
  end

  def create_custom_payment_link 
    begin
      @customer = Customer.find_by(id: params[:customer_id])
      amount_cents = (params[:amount].to_f * 100 ).to_i
      percentage = params[:percentage].present? ? params[:percentage] : 10
      platform_fee_cents = (percentage.to_i * params[:amount].to_f).to_i     
      connected_account_id = current_user.try(:stripe_user_id)
      session = Stripe::Checkout::Session.create(
        {
          mode: "payment",
          payment_method_types: ["card"],
          customer: @customer.try(:customer_id), # cus_... that exists on connected account
      
          payment_method_options: {
            card: {
              request_three_d_secure: current_user.require_3ds? ? "any" : "automatic"
            }
          },
          # consent_collection: {
          #   terms_of_service: "required"
          # },

          line_items: [{
            price_data: {
              currency: ENV["CURRENCY"],
              unit_amount: amount_cents,
              product_data: {
                name: params[:name],
                description: params[:description].presence || params[:name]
              }
            },
            quantity: 1
          }],

          shipping_address_collection: {
            allowed_countries: ["US", "ID", "AU", "SG"]
          },
      
          success_url: ENV["SUCCESS_URL"] + "?session_id={CHECKOUT_SESSION_ID}",
          cancel_url:  ENV["CANCEL_URL"]  + "?session_id={CHECKOUT_SESSION_ID}",
      
          payment_intent_data: {
            application_fee_amount: platform_fee_cents,
            setup_future_usage: "off_session" # saves new card for future; helps “saved cards show”
          }
        },
        { stripe_account: connected_account_id }  # ✅ connected account context
      )
      
      session_id = session.id # ex: cs_test_123

      cookies[:checkout_session_id] = session_id
      redirect_to success_path(id: params[:customer_id])
      
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

  def remove_user
    begin
      @user = User.find_by(id: params[:format])
      if @user.present?
        @stripe_user_id = @user.stripe_user_id if @user.stripe_user_id.present?
        @user.delete
        Stripe::Account.delete(@stripe_user_id)
      end
    rescue => e 
    end
    redirect_to users_path
  end

  def remove_customer
    @customer = Customer.find_by(id: params[:format])
    if @customer.present? 
      # connected_acct_id = User.find(@customer.user_id).try(:stripe_user_id)
      # customer_id = @customer.try(:customer_id)
      @customer.delete
      redirect_to customers_path
      # begin
      #   Stripe::Customer.delete(customer_id, {}, { stripe_account: connected_acct_id})
      #   @customer.delete
      #   redirect_to customers_path
      # rescue Stripe::CardError => e
      #   flash[:error] = e.message
      #   redirect_to customers_path
      # rescue Stripe::InvalidRequestError => e
      #   flash[:error] = e.message
      #   redirect_to customers_path
      # rescue Stripe::RateLimitError => e
      #   flash[:error] = e.message
      #   redirect_to customers_path
      # rescue Stripe::AuthenticationError => e
      #   flash[:error] = e.message
      #   redirect_to customers_path
      # rescue Stripe::APIConnectionError => e
      #   flash[:error] = e.message
      #   redirect_to customers_path
      # rescue Stripe::StripeError => e
      #   flash[:error] = e.message
      #   redirect_to customers_path
      # rescue => e
      #   flash[:error] = "System Error"
      #   redirect_to customers_path
      # end
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
      redirect_to success_path(id: params[:id])
    rescue => e
      flash[:error] = e.message.presence || "System Error"
      redirect_to cancel_path
    end
  end

  def balance  

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
            payment_method_types: ['card'],
            payment_method_options: {
              card: {
                request_three_d_secure: current.try(:require_3ds) ? 'any' : 'automatic'
              }
            }
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
    @user_id = current_user.try(:referral_id).present? ? current_user.try(:referral_id) : current_user.try(:id)
    @customer = Customer.create(email: params[:email], 
      name: params[:name], 
      phone: params[:phone], 
      line1: params[:line1], 
      line2: params[:line2], 
      city: params[:city], 
      state: params[:state], 
      postal_code: params[:postal_code], 
      country: params[:country], 
      user_id: @user_id)
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
        { stripe_account: User.find_by(id: @customer.try(:user_id)).try(:stripe_user_id) }
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
          allowed_countries: ["US", "ID", "AU", "SG"]
        },
        success_url: ENV['CUSTOMER_CREATION_SUCCESS'] + "?session_id={CHECKOUT_SESSION_ID}&id=#{@customer.try(:id)}",
        cancel_url: ENV['CANCEL_URL'] + "?session_id={CHECKOUT_SESSION_ID}&id=#{@customer.try(:id)}",
      },
      { stripe_account: connected_acct_id }
    )
    cookies[:customer_url] = customer_id
    @customer.update(customer_card_url: session.url)
    redirect_to success_path(id: customer_id)
  end

  def checkout_url
    @customer = Customer.find_by(customer_id: params[:id])
    redirect_to @customer.customer_card_url if @customer.present? && @customer.customer_card_url.present?
  end

  def stripe_invoice_url
    @invoice = Invoice.find_by(unique_id: params[:id])
    redirect_to @invoice.invoice_url if @invoice.present? && @invoice.invoice_url.present?
  end

  def all_users
    @users = User.all
  end

  def invoice
    @customers = Customer.where(user_id: current_user.try(:id)).order(:name)
  end

  def add_note
    @customer = Customer.find_by(id: params[:customer_id])
    if @customer.present?
      @customer.update(note: params[:note])
    end

    redirect_to customers_path

  end

  def create_payment_link
    begin
      @unique_id = SecureRandom.hex(6).upcase

        # 1) Vendor context
      connected_acct_id = current_user.stripe_user_id

      # 2) Customer selected from your DB (must belong to this vendor)
      customer = Customer.find_by(id: params[:customer_id])
      stripe_customer_id = customer.customer_id # cus_...

      pm_id = customer.payment_method 

      # 3) Invoice line item (simple single-item example)
      description  = params[:description].presence || "Invoice"

      amount_cents = (params[:amount].to_f * 100).round

      percentage = (params[:percentage].presence || 10).to_f
      application_fee_cents = (amount_cents * (percentage / 100.0)).round

      if params[:type] == "automatic"
        # 2) Create invoice set to auto-charge
        invoice = Stripe::Invoice.create(
          {
            customer: stripe_customer_id,

            # IMPORTANT: auto-charge, not send_invoice
            collection_method: "charge_automatically",

            # Use the saved card you already have
            default_payment_method: pm_id,

            # Your custom description (shows on invoice; payment objects still often show "Payment for Invoice")
            description: description,

            # If you need Connect fee
            application_fee_amount: application_fee_cents,

            # Let Stripe finalize & attempt payment automatically, OR you can finalize+pay yourself below
            auto_advance: false,

            shipping_details: {
              name: params[:shipping_name],
              address: {
                line1:    params[:shipping_line1],
                city:     params[:shipping_city],
                state:    params[:shipping_state],
                postal_code: params[:shipping_postal_code],
                country:  params[:shipping_country]
              }
            },
          },
          { stripe_account: connected_acct_id }
        )

        invoice_item = Stripe::InvoiceItem.create(
          {
            customer: stripe_customer_id,
            invoice: invoice.id, 
            amount: amount_cents,
            currency: ENV["CURRENCY"] || "usd",
            description: description
          },
          { stripe_account: connected_acct_id }
        )

        # 3) Finalize invoice (draft -> open)
        finalized = Stripe::Invoice.finalize_invoice(
          invoice.id,
          {},
          { stripe_account: connected_acct_id }
        )

        # 4) Pay now (forces attempt immediately)
        paid = Stripe::Invoice.pay(
          finalized.id,
          {
            off_session: true,
            payment_method: pm_id
          },
          { stripe_account: connected_acct_id }
        )
      else  
        # 5) Create the Invoice (draft) 
        invoice = Stripe::Invoice.create(
          {
            description: description,
            customer: stripe_customer_id,
            collection_method: "send_invoice",
            days_until_due: 7,
            application_fee_amount: application_fee_cents, # optional
            auto_advance: false,
            shipping_details: {
              name: params[:shipping_name],
              address: {
                line1:    params[:shipping_line1],
                city:     params[:shipping_city],
                state:    params[:shipping_state],
                postal_code: params[:shipping_postal_code],
                country:  params[:shipping_country]
              }
            },
          },
          { stripe_account: connected_acct_id }
        )

        # 4) Create an Invoice Item on the connected account 
        invoice_item = Stripe::InvoiceItem.create(
          {
            customer: stripe_customer_id,
            invoice: invoice.id, 
            amount: amount_cents,
            currency: ENV["CURRENCY"] || "usd",
            description: description
          },
          { stripe_account: connected_acct_id }
        )

        # 6) Finalize the invoice (moves draft -> open) 
        finalized = Stripe::Invoice.finalize_invoice(
          invoice.id,
          {},
          { stripe_account: connected_acct_id }
        )
      end

      @invoice = Invoice.create(customer_id: params[:customer_id], unique_id: @unique_id, description: params[:description], amount: amount_cents, currency: ENV['CURRENCY'], user_id: current_user.try(:id), invoice_url: finalized.hosted_invoice_url)

      cookies[:invoice_url] = @invoice.unique_id
      redirect_to success_path(id: params[:customer_id]), notice: "Invoice created successfully."
    rescue Stripe::CardError => e
      if @invoice.present?
        @invoice.delete
      end
      flash[:error] = e.message
      redirect_to invoices_path
    rescue Stripe::InvalidRequestError => e
      if @invoice.present?
        @invoice.delete
      end
      flash[:error] = e.message
      redirect_to invoices_path
    rescue Stripe::RateLimitError => e
      if @invoice.present?
        @invoice.delete
      end
      flash[:error] = e.message
      redirect_to invoices_path
    rescue Stripe::AuthenticationError => e
      if @invoice.present?
        @invoice.delete
      end
      flash[:error] = e.message
      redirect_to invoices_path
    rescue Stripe::APIConnectionError => e
      if @invoice.present?
        @invoice.delete
      end
      flash[:error] = e.message
      redirect_to invoices_path
    rescue Stripe::StripeError => e
      if @invoice.present?
        @invoice.delete
      end
      flash[:error] = e.message
      redirect_to invoices_path
    rescue => e
      if @invoice.present?
        @invoice.delete
      end
      flash[:error] = "System Error"
      redirect_to invoices_path
    end
  end

  def success
    if params[:vendor].present?
      @user = User.find_by(id: params[:vendor_id])
      begin
        # 1) Get the Checkout Session that just finished
        checkout_session = Stripe::Checkout::Session.retrieve(
          params[:session_id],
        )
    
        # 2) It will have a setup_intent; fetch it
        if checkout_session.setup_intent.present?
          si = Stripe::SetupIntent.retrieve(
            checkout_session.setup_intent
          )
    
          # 3) Pull the exact payment method saved during Checkout
          pm_id = si.payment_method
          if pm_id.present?
            # 4) Save it locally and make it default for the customer
            @user.update!(payment_method: pm_id)
            pm = Stripe::PaymentMethod.retrieve(pm_id)
            if pm.present? && pm["card"].present?
              @user.update(last4: pm["card"]["last4"], brand: pm["card"]["brand"])
            end
            Stripe::Customer.update(
              @user.vendor_id,
              { invoice_settings: { default_payment_method: pm_id } },
            )
          end
        end
        redirect_to success_path(id: params[:id])
      rescue => e
        flash[:error] = e.message.presence || "System Error"
        redirect_to cancel_path
      end
    end
    if cookies[:customer_url].present? 
      @customer = Customer.find_by(customer_id: cookies[:customer_url])
      @session_url = "#{ENV['WEBSITE_URL']}" + "/checkout/" + @customer.try(:customer_id) if @customer.present?
      cookies.delete :customer_url
    end
    if cookies[:invoice_url].present? 
      @invoice = Invoice.find_by(unique_id: cookies[:invoice_url])
      @invoice_url = "#{ENV['WEBSITE_URL']}" + "/stripe_invoice/" + @invoice.try(:unique_id) if @invoice.present?
      cookies.delete :invoice_url
    end
    if cookies[:checkout_session_id].present? 
      @checkout_session_url = "#{ENV['WEBSITE_URL']}" + "/redirect_checkout/" + cookies[:checkout_session_id]
      cookies.delete :checkout_session_id
    end
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
      if current_user.try(:stripe_user_id).present?
        # Retrieve the current balance from Stripe
        balance = Stripe::Balance.retrieve({}, { stripe_account: current_user.try(:stripe_user_id) })

        # Pass the balance to the view
        @available_balance = balance.available.first.amount / 100.0  # Available balance in the default currency
        @pending_balance = balance.pending.first.amount / 100.0  # Pending balance in the default currency
        @currency = balance.pending.first.currency
      else 
        @available_balance = 0  # Available balance in the default currency
        @pending_balance = 0  # Pending balance in the default currency
      end

    rescue Stripe::StripeError => e
      flash[:alert] = "Error retrieving balance: #{e.message}"
      redirect_to new_payment_path
    end
  end

  def payout

  end

  def create_small_payout
    if current_user.try(:stripe_user_id).present?
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
    else   
      flash[:error] = "No balance available"
    end
    redirect_to payouts_path
  end

  def create_payout
    if current_user.try(:stripe_user_id).present?
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
    else   
      flash[:error] = "No balance available"
    end
  end

  private
    def validate_admin_user!
      if current_user.nil? || !current_user.admin?
        flash[:alert] = 'Permission Denied! Its only for admin.'
        sign_out(current_user)
        redirect_to unauthenticated_root_path
      end
    end

    def validate_vendor_user!
      if current_user.nil? || (!current_user.vendor? && !current_user.admin?)
        flash[:alert] = 'Permission Denied! Its only for vendor.'
        sign_out(current_user)
        redirect_to unauthenticated_root_path
      end
    end

end