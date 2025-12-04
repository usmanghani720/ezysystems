class HomeController < ApplicationController
		layout "home"
  
		def index
		end

		def contact
		end

		def privacy 
			file_path = Rails.root.join(ENV['PRIVACY_DOC'])
			@privacy_html = File.read(file_path)
		end

		def terms 
			file_path = Rails.root.join(ENV['TERMS_DOC'])
			@terms_html = File.read(file_path)
		end

		def pricing 

		end

		def custom_portal 

		end

		def customer_messaging

		end

		def marketing_tools

		end

		def marketing_messaging

		end

		def payment

		end

		def invoicing

		end

		def expenses

		end

		def bookkeeping

		end
  end
  