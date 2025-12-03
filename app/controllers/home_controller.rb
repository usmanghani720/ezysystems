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
  end
  