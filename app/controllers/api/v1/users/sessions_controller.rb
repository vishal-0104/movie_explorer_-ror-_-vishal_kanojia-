class Api::V1::Users::SessionsController < Devise::SessionsController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_api_v1_user_for_destroy, only: [:destroy]
  respond_to :json

  def create
    Rails.logger.info "Login params: #{params.inspect}"
    warden.logout if warden.authenticated?(:user)
  
    email = params[:session]&.dig(:email)&.downcase
    password = params[:session]&.dig(:password)
  
    unless email && password
      render json: { error: 'Email and password are required' }, status: :unprocessable_entity
      return
    end
  
    resource = User.find_by(email: email)
    unless resource&.valid_password?(password)
      render json: { error: 'Invalid email or password' }, status: :unauthorized
      return
    end
  
    self.resource = resource
    device_token = params[:device_token]
    if device_token.present?
      existing_user = User.find_by(device_token: device_token)
      if existing_user && existing_user != resource
        existing_user.update(device_token: nil)
      end
      resource.update(device_token: device_token)
    end
  
    sign_in(resource_name, resource)
    Rails.logger.info "Signed in user #{resource.id}, email: #{resource.email}"
    respond_with(resource)
  end

  def destroy
    unless @current_user
      render json: { message: 'Already signed out or token invalid' }, status: :ok
      return
    end
  
    begin
      user = @current_user
      auth_header = request.headers['Authorization']
      token = auth_header&.split('Bearer ')&.last
  
      if token
        jwt_secret = Rails.application.credentials.jwt_secret || ENV['JWT_SECRET']
        decoded_token = JWT.decode(token, jwt_secret, true, algorithm: 'HS256').first
        jti = decoded_token['jti']
  
        BlacklistedToken.create!(
          jti: jti,
          user: user,
          expires_at: Time.at(decoded_token['exp']).utc
        )
      else
        Rails.logger.warn "No token found in Authorization header during sign-out for user #{user.id}"
      end
  
      user.update(device_token: nil) if user.device_token.present?
      sign_out(:user)
  
      Rails.logger.info "Signed out user #{user.id}, blacklisted jti: #{jti}"
      render json: { message: 'Successfully signed out' }, status: :ok
    rescue JWT::DecodeError => e
      Rails.logger.error "JWT decode error during sign-out: #{e.message}"
      render json: { error: 'Invalid token' }, status: :unprocessable_entity
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Failed to blacklist token: #{e.message}"
      render json: { error: 'Failed to revoke token' }, status: :unprocessable_entity
    rescue StandardError => e
      Rails.logger.error "Sign-out error: #{e.message}"
      render json: { error: 'An unexpected error occurred' }, status: :internal_server_error
    end
  end

  private

  def authenticate_api_v1_user_for_destroy
    auth_header = request.headers['Authorization']
    Rails.logger.info "Authorization header: #{auth_header}"

    if auth_header.blank? || !auth_header.start_with?('Bearer ')
      @current_user = nil
      return
    end

    token = auth_header.split('Bearer ').last
    Rails.logger.info "JWT token: #{token}"

    begin
      jwt_secret = Rails.application.credentials.jwt_secret || ENV['JWT_SECRET']
      decoded_token = JWT.decode(token, jwt_secret, true, algorithm: 'HS256').first
      user_id = decoded_token['user_id']

      @current_user = User.find_by(id: user_id)
      Rails.logger.info "Current user: #{@current_user&.inspect}"
    rescue JWT::ExpiredSignature
      @current_user = nil
    rescue JWT::DecodeError => e
      Rails.logger.error "JWT error: #{e.message}"
      @current_user = nil
    rescue StandardError => e
      Rails.logger.error "Authentication error: #{e.message}"
      @current_user = nil
    end
  end

  def respond_with(resource, _opts = {})
    if resource.persisted?
      Rails.logger.info "Responding with user email: #{resource.email}"
      render json: {
        token: request.env['warden-jwt_auth.token'],
        user: user_response(resource)
      }, status: :ok
    else
      render json: { error: 'Invalid email or password' }, status: :unauthorized
    end
  end

  def user_response(user)
    user.as_json(only: [:id, :email, :first_name, :last_name, :mobile_number, :role, :created_at, :updated_at])
  end
end