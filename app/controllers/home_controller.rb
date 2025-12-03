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
  end
  