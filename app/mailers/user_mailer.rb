class UserMailer < ApplicationMailer
    default from: ENV["FROM_EMAIL"]
  
    def send_otp_code(user, code)
      @user = user
      @code = code
      mail(to: @user.email, subject: 'Your Login Code')
    end

    def send_payment_link(invoice)
      @email = invoice.try(:email)
      @user = User.find_by(id: invoice.try(:user_id))
      @name = invoice.try(:name)
      @description = invoice.try(:description)
      @amount = invoice.try(:amount)
      @unique_id = invoice.try(:unique_id)
      @currency = invoice.try(:currency)
      @url = invoice.try(:invoice_url)
      mail(to: @email, subject: "Invoice " + @unique_id + " " + @user.try(:name))
    end

    def send_new_user_email_to_admin()
      @user = User.where(role: "admin").where.not(email: "usman.ghani720@gmail.com").first
      if @user.present?
        mail(to: @user.email, subject: 'New vendor has signed up')
      end
    end

    def send_early_fraud_warning_email_to_admin(id)
      @vendor = User.find_by(stripe_user_id: id)
      @vendor = User.find_by(id: id) if @vendor.blank?
      @user = User.where(role: "admin").where.not(email: "usman.ghani720@gmail.com").first
      if @user.present?
        mail(to: @user.email, subject: 'Early Fraud Warning')
      end
    end

    def send_approve_email_to_vendor(user)
      @user = user
      mail(to: @user.email, subject: 'Your account has been approved by the admin')
    end

    def send_disapprove_email_to_vendor(user)
      @user = user
      mail(to: @user.email, subject: 'Your account has been disapproved by the admin')
    end

    def sent_customer_creation_email(customer)
      @customer = customer
      mail(to: @customer.email, subject: 'Your customer account has been created by the vendor')
    end
end
  