class Api::V1::Users::RegistrationsController < Devise::RegistrationsController
  skip_before_action :verify_authenticity_token
  respond_to :json

  def create
    build_resource(sign_up_params)
    resource.jti = SecureRandom.uuid
    resource.save
    if resource.persisted?
      sign_in(resource_name, resource)
      token = Warden::JWTAuth::UserEncoder.new.call(resource, :user, nil)
      request.env['warden-jwt_auth.token'] = token 
    end
    respond_with(resource)
  end

  private

  def sign_up_params
    params.require(:user).permit(:email, :password, :first_name, :last_name, :mobile_number, :role)
  end

  def respond_with(resource, _opts = {})
    if resource.persisted?
      render json: {
        token: request.env['warden-jwt_auth.token'],
        user: user_response(resource)
      }, status: :created
    else
      render json: { errors: resource.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def user_response(user)
    user.as_json(only: [:id, :email, :first_name, :last_name, :mobile_number, :role, :created_at, :updated_at])
  end
end