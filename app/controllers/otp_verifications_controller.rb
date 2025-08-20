class OtpVerificationsController < ApplicationController
    before_action :authenticate_user!
  
    def new
      @user = User.find(session[:otp_user_id])
    end
  
    def verify
      @user = User.find(session[:otp_user_id])
      if @user.otp_code == params[:otp_code]
        session[:otp_valid] = true
        sign_in(@user)
        session.delete(:otp_user_id)
        session.delete(:otp_valid) 
        redirect_to root_path, notice: 'Logged in successfully'
      else
        sign_out(current_user)
        redirect_to root_path, notice: 'Invalid code, please try again'
      end
    end
  end
  