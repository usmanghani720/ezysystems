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

		def customer_management

		end

		def jobs

		end

		def assignment_scheduling

		end

		def job_records

		end

		def professional_window_cleaner_software

		end

		def bin_cleaning_software

		end

		def carpet_cleaning_software

		end

		def exterior_cleaning

		end

		def cleaning_housekeeping_maid_service_software

		end

		def mobile_cleaning_services

		end
  end
  