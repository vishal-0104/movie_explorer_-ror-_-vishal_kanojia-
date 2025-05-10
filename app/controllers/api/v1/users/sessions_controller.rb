class Api::V1::Users::SessionsController < Devise::SessionsController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_api_v1_user!, only: [:destroy]
  respond_to :json

  def create
    email = params[:email] || params[:session]&.[](:email)
    password = params[:password] || params[:session]&.[](:password)

    self.resource = User.authenticate(email, password)
    if resource
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
      unless payload && payload['jti']
        render json: { error: 'Invalid JWT payload' }, status: :unprocessable_entity
        return
      end

      User.revoke_jwt(payload, current_api_v1_user)
      response.set_header('X-Revoked', 'true')
      response.set_header('X-JTI', payload['jti'])
      sign_out
      render json: { message: 'Successfully signed out', jti: payload['jti'] }, status: :ok
    rescue JWT::ExpiredSignature
      begin
        payload = JWT.decode(token, ENV['JWT_SECRET'], false, algorithm: 'HS256').first
        unless payload && payload['jti']
          render json: { error: 'Invalid JWT payload' }, status: :unprocessable_entity
          return
        end

        User.revoke_jwt(payload, current_api_v1_user)
        response.set_header('X-Revoked', 'true')
        response.set_header('X-JTI', payload['jti'])
        sign_out
        render json: { message: 'Successfully signed out (expired token)', jti: payload['jti'] }, status: :ok
      rescue JWT::DecodeError => e
        Rails.logger.error "JWT Decode Error: #{e.message}"
        render json: { error: 'Invalid JWT token' }, status: :unprocessable_entity
      end
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