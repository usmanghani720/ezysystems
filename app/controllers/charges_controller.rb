class ChargesController < ApplicationController
    require "stripe"
    include ApplicationHelper
    Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
  
      def new
        @customer = Customer.find_by(id: params[:id])
        if @customer.present?
          connected_acct_id = User.find_by(id: @customer.try(:user_id)).try(:stripe_user_id)
          customer_id = @customer.customer_id
        end
    
        session = Stripe::Checkout::Session.create(
          {
            mode: "setup",
            customer: customer_id,
            payment_method_types: ["card"],
            success_url: ENV['SUCCESS_URL'] + "?session_id={CHECKOUT_SESSION_ID}&id=#{@customer.try(:id)}",
            cancel_url: ENV['CANCEL_URL'] + "?session_id={CHECKOUT_SESSION_ID}&id=#{@customer.try(:id)}",
          },
          { stripe_account: connected_acct_id }
        )
    
        redirect_to session.url
      end
  
      def handle_payment_methods
        @customer = Customer.find_by(id: params[:customer_id])
        @account_id = User.find_by(id: @customer.try(:user_id)).try(:stripe_user_id)
        begin
          si = Stripe::SetupIntent.create(
            {
              customer: @customer.customer_id,
              payment_method_types: ["card"],
              usage: "off_session"
            },
            { stripe_account: account_id }
          )
          render json: { clientSecret: si['client_secret'] }
        rescue Stripe::CardError => e
          flash[:error] = e.message
          render json: { clientSecret: nil}
        rescue Stripe::InvalidRequestError => e
          flash[:error] = e.message
          render json: { clientSecret: nil}
        rescue Stripe::RateLimitError => e
          flash[:error] = e.message
          render json: { clientSecret: nil}
        rescue Stripe::AuthenticationError => e
          flash[:error] = e.message
          render json: { clientSecret: nil}
        rescue Stripe::APIConnectionError => e
          flash[:error] = e.message
          render json: { clientSecret: nil}
        rescue Stripe::StripeError => e
          flash[:error] = e.message
          render json: { clientSecret: nil}
        end
      end
  
      def handle_payment_methods_confirm
        @intent = Intent.find_by(payment_intent_id: cookies[:payment_intent_id]) || @intent = Intent.find_by(payment_intent_id: params[:payment_intent])
        if @intent.present?
          payment_intent = Stripe::PaymentIntent.retrieve(@intent.try(:payment_intent_id))
          if payment_intent && payment_intent["status"] == "succeeded"
						@customer_details = payment_intent["shipping"]
						@invoice = Invoice.find_by(id: cookies[:invoice_id])
						if @invoice.present?
              connected_account_id = User.find_by(id: @invoice.try(:user_id)).try(:stripe_user_id)
              transfer_amount = (payment_intent.amount - payment_intent.application_fee_amount) / 100.0
              pdf_content = generate_pdf(payment_intent, transfer_amount)
              @invoice.update(status: 'paid', payment_intent_id: @intent.try(:payment_intent_id))
              UserMailer.send_payment_successful_email_to_freelancer(@invoice, pdf_content).deliver_now
              UserMailer.send_payment_successful_email_to_client(@invoice).deliver_now

              if !@customer_details.blank?
                @invoice.update(city: @customer_details["address"]["city"], 
                state: @customer_details["address"]["state"],
                country: @customer_details["address"]["country"],
                postal_code: @customer_details["address"]["postal_code"],
                line1: @customer_details["address"]["line1"],
                line2: @customer_details["address"]["line2"],
                phone: @customer_details["phone"],
						    )
              end
						end
            @success = true
            @intent.delete
            cookies.delete :invoice_id
            cookies.delete :payment_intent_id
          else
            if payment_intent && payment_intent["last_payment_error"] && payment_intent["last_payment_error"]["message"]
              flash[:error] = payment_intent["last_payment_error"]["message"]
            elsif payment_intent && payment_intent["status"] == "processing"
              flash[:notice] = "Payment Processing"
            elsif payment_intent && payment_intent["status"] == "requires_action"
              flash[:notice] = "Payment requires further action"
              begin
                @verification_url = payment_intent["next_action"]["verify_with_microdeposits"]["hosted_verification_url"]
              rescue => e 
                @verification_url = ""
              end
            elsif payment_intent["status"] == "requires_payment_method"
              flash[:error] = "Requires Payment Method"
            end
          end
        end
      end

      def generate_pdf(payment_intent, transfer_amount)
        Prawn::Document.new do |pdf|
          pdf.text "Betalingsbewijs", size: 20, style: :bold, align: :center
          pdf.move_down 20
    
          pdf.text "Betalingsdatum: #{Time.at(payment_intent.created).strftime('%B %d, %Y')}"
          pdf.move_down 10
          pdf.text "Totaal Betaald Bedrag: #{format_amount(payment_intent.amount, payment_intent.currency)}"
          pdf.move_down 10
          pdf.text "Bedrag Overgemaakt aan U: #{transfer_amount.round(2)} #{payment_intent.currency.upcase}"
          pdf.move_down 10
          pdf.text "E-mailadres : #{User.find_by(id: @invoice.try(:user_id)).try(:email)}"
          pdf.move_down 10
          pdf.text "Bedankt voor de samenwerking!"
          pdf.move_down 10
          pdf.text "Team AppointmentsSetter.nl"
        end.render
      end
  
  end
  