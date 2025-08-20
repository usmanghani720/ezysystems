class PaymentsController < ApplicationController
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

  def make_payment
    @customer = Customer.find_by(id: params[:id])
    connected_acct_id = User.find_by(id: @customer.try(:user_id)).try(:stripe_user_id)
    customer = Stripe::Customer.retrieve(
      @customer.customer_id,
      { stripe_account: connected_acct_id } # opts: target the connected account
    )
    if @customer.payment_method.blank?
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
    @customer = Customer.create(email: params[:email], name: params[:name], phone: params[:phone], user_id: current_user.try(:id))
    begin  
      customer = Stripe::Customer.create(
        {
          name:  params[:name],
          email: params[:email],
          phone: params[:phone],
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
    UserMailer.sent_customer_creation_email(@customer).deliver_now
    redirect_to customers_path
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
      redirect_to root_path
    rescue Stripe::InvalidRequestError => e
      if @invoice.present?
        @invoice.delete
      end
      flash[:error] = e.message
      redirect_to root_path
    rescue Stripe::RateLimitError => e
      if @invoice.present?
        @invoice.delete
      end
      flash[:error] = e.message
      redirect_to root_path
    rescue Stripe::AuthenticationError => e
      if @invoice.present?
        @invoice.delete
      end
      flash[:error] = e.message
      redirect_to root_path
    rescue Stripe::APIConnectionError => e
      if @invoice.present?
        @invoice.delete
      end
      flash[:error] = e.message
      redirect_to root_path
    rescue Stripe::StripeError => e
      if @invoice.present?
        @invoice.delete
      end
      flash[:error] = e.message
      redirect_to root_path
    rescue => e
      if @invoice.present?
        @invoice.delete
      end
      flash[:error] = "System Error"
      redirect_to root_path
    end
    UserMailer.send_payment_link(@invoice).deliver_now
    redirect_to root_path
  end

  def success
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