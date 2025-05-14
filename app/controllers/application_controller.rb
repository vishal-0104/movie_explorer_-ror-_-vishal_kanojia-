class ApplicationController < ActionController::Base
  before_action :set_default_response_format

  def authenticate_api_v1_user!
    auth_header = request.headers['Authorization']
    Rails.logger.info "Authorization header: #{auth_header}"
  
    if auth_header.blank? || !auth_header.start_with?('Bearer ')
      render json: { error: 'No token provided. Please sign in.' }, status: :unauthorized
      return
    end
  
    token = auth_header.split('Bearer ').last
    Rails.logger.info "JWT token: #{token}"
  
    begin
      jwt_secret = Rails.application.credentials.jwt_secret || ENV['JWT_SECRET']
      decoded_token = JWT.decode(token, jwt_secret, true, algorithm: 'HS256').first
      user_id = decoded_token['user_id']
      jti = decoded_token['jti']
  
      user = User.find_by(id: user_id)
      if user
        if BlacklistedToken.revoked?(decoded_token)
          Rails.logger.info "Token revoked: jti #{jti} is blacklisted"
          render json: { error: 'Token has been revoked. Please sign in again.' }, status: :unauthorized
          return
        end
        @current_user = user
        Rails.logger.info "Current user: #{user.inspect}"
      else
        render json: { error: 'Invalid token: User not found.' }, status: :unauthorized
      end
    rescue JWT::ExpiredSignature
      render json: { error: 'Token has expired.' }, status: :unauthorized
    rescue JWT::DecodeError => e
      Rails.logger.error "JWT error: #{e.message}"
      render json: { error: "Invalid token: #{e.message}" }, status: :unauthorized
    rescue StandardError => e
      Rails.logger.error "Authentication error: #{e.message}"
      render json: { error: 'Authentication failed.' }, status: :unauthorized
    end
  end

  private

  def set_default_response_format
    request.format = :json if request.path.start_with?('/api')
  end
end