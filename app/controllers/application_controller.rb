class ApplicationController < ActionController::Base
before_action :authenticate_api_v1_user!

  def authenticate_api_v1_user!
    Rails.logger.info "Authorization header: #{request.headers['Authorization']}"
    Rails.logger.info "JWT token: #{request.headers['Authorization']&.split('Bearer ')&.last}"
    super
    Rails.logger.info "Current user: #{current_api_v1_user&.inspect}"
  rescue JWT::DecodeError => e
    Rails.logger.error "JWT error: #{e.message}"
    render json: { error: 'Unauthorized', errors: ['Invalid token'] }, status: :unauthorized
  rescue StandardError => e
    Rails.logger.error "Authentication error: #{e.message}"
    render json: { error: 'Unauthorized', errors: ['Authentication failed'] }, status: :unauthorized
  end
end
