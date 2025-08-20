class ApplicationController < ActionController::Base
    skip_before_action :verify_authenticity_token
    before_action :configure_permitted_parameters, if: :devise_controller?

    def configure_permitted_parameters
        devise_parameter_sanitizer.permit(:sign_up, keys: [:name, :country])
        devise_parameter_sanitizer.permit(:account_update, keys: [:name, :country]) # if you want to allow name to be updated
    end

		def after_sign_in_path_for(resource_or_scope)
			stored_location_for(resource_or_scope) || super
		end
end

