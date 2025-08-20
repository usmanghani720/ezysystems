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

    def send_payment_successful_email_to_freelancer(invoice, pdf_content)
      @user = User.find_by(id: invoice.try(:user_id))
      @email = @user.try(:email)
      @name = @user.try(:name)
      attachments["receipt"] = { mime_type: 'application/pdf', content: pdf_content }
      mail(to: @email, subject: "Onderwerp: ✅ Je factuur is betaald!")
    end

    def send_payment_successful_email_to_client(invoice)
      @email = invoice.try(:email)
      @name = invoice.try(:name)
      mail(to: @email, subject: "Betaling ontvangen – dit is wat je kunt verwachten")
    end

    def send_onboarding_url(email, onboarding_url)
      @email = email
      @onboarding_url = onboarding_url
      mail(to: email, subject: "Maak uw onboarding compleet")
    end

    def send_new_user_email_to_admin()
      @user = User.find_by(role: "admin")
      if @user.present?
        mail(to: @user.email, subject: 'New vendor has signed up')
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
  