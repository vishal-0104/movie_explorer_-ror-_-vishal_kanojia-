# app/controllers/api/v1/users/sessions_controller.rb
class Api::V1::Users::SessionsController < Devise::SessionsController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_api_v1_user!, only: [:destroy]
  respond_to :json

  def create
    # Extract email and password from params (handle both root and nested session)
    email = params[:email] || params[:session]&.[](:email)
    password = params[:password] || params[:session]&.[](:password)

    # Log params for debugging (remove in production)
    Rails.logger.debug "Login params: email=#{email}, password=#{password.present? ? '[REDACTED]' : 'missing'}"

    # Authenticate using User model's method
    self.resource = User.authenticate(email, password)

    if resource
      sign_in(resource_name, resource)
      respond_with(resource)
    else
      Rails.logger.debug "Authentication failed for email: #{email}"
      render json: { error: 'Invalid email or password' }, status: :unauthorized
    end
  end

  def destroy
    if current_api_v1_user
      # Revoke the JWT token
      token = request.headers['Authorization']&.split(' ')&.last
      if token
        begin
          payload = JWT.decode(token, ENV['JWT_SECRET'], true, algorithm: 'HS256').first
          User.revoke_jwt(payload, current_api_v1_user)
        rescue JWT::DecodeError => e
          Rails.logger.error "JWT decode error: #{e.message}"
          render json: { error: 'Invalid token' }, status: :unprocessable_entity and return
        end
      end
      sign_out
      respond_to_on_destroy
    else
      render json: { error: 'Not authenticated' }, status: :unauthorized
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

  def respond_to_on_destroy
    head :no_content
  end
end