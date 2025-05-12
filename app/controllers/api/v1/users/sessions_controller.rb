class Api::V1::Users::SessionsController < Devise::SessionsController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_api_v1_user!, only: [:destroy]
  respond_to :json

  def create
    email = params[:email] || params[:session]&.[](:email)
    password = params[:password] || params[:session]&.[](:password)
    device_token = params[:device_token]
  
    self.resource = User.authenticate(email, password)
    if resource
      # If another user already has this token, remove it
      if device_token.present?
        existing_user = User.find_by(device_token: device_token)
        if existing_user && existing_user != resource
          existing_user.update(device_token: nil)
        end
  
        resource.update(device_token: device_token)
      end
  
      sign_in(resource_name, resource)
      respond_with(resource)
    else
      render json: { error: 'Invalid email or password' }, status: :unauthorized
    end
  end
  

  def destroy
    unless current_api_v1_user
      render json: { error: 'Not authenticated' }, status: :unauthorized
      return
    end
  
    token = request.headers['Authorization']&.split(' ')&.last
    unless token
      render json: { error: 'Authorization token missing' }, status: :bad_request
      return
    end
  
    begin
      payload = JWT.decode(token, ENV['JWT_SECRET'], true, algorithm: 'HS256').first
      User.revoke_jwt(payload, current_api_v1_user)
  
      # Clear device token
      current_api_v1_user.update(device_token: nil)
  
      response.set_header('X-Revoked', 'true')
      response.set_header('X-JTI', payload['jti'])
      sign_out
      render json: { message: 'Successfully signed out', jti: payload['jti'] }, status: :ok
  
    rescue JWT::ExpiredSignature
      payload = JWT.decode(token, ENV['JWT_SECRET'], false, algorithm: 'HS256').first
      User.revoke_jwt(payload, current_api_v1_user)
  
      current_api_v1_user.update(device_token: nil)
  
      response.set_header('X-Revoked', 'true')
      response.set_header('X-JTI', payload['jti'])
      sign_out
      render json: { message: 'Successfully signed out (expired token)', jti: payload['jti'] }, status: :ok
  
    rescue JWT::DecodeError => e
      Rails.logger.error "JWT Decode Error: #{e.message}"
      render json: { error: 'Invalid JWT token' }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error "Unexpected Error: #{e.message}"
      render json: { error: 'An unexpected error occurred' }, status: :internal_server_error
    end
  end
  

  private

  def respond_with(resource, _opts = {})
    render json: {
      token: resource.generate_jwt,
      user: user_response(resource)
    }, status: :ok
  end

  def user_response(user)
    user.as_json(only: [:id, :email, :first_name, :last_name, :mobile_number, :role, :created_at, :updated_at])
  end
end