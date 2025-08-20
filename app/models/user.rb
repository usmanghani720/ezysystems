class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :trackable

    def admin?
      self.role == "admin"
    end

    def send_two_factor_authentication_code(code)
      UserMailer.send_otp_code(self, code).deliver_now
    end

    def active_for_authentication?
      super && approved?
    end
  
    def inactive_message
      approved? ? super : :not_approved
    end

end
