class ApplicationMailer < ActionMailer::Base
  default from: ENV["SENDGRID_EMAIL"]
  layout 'mailer'
end
