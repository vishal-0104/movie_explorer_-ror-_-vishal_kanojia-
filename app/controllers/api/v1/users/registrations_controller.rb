# app/controllers/api/v1/users/registrations_controller.rb
class Api::V1::Users::RegistrationsController < Devise::RegistrationsController
  skip_before_action :verify_authenticity_token
  respond_to :json

  def create
    build_resource(sign_up_params)
    resource.save
    respond_with(resource)
  end

  private

  def sign_up_params
    params.require(:user).permit(:email, :password, :first_name, :last_name, :mobile_number, :role)
  end

  def respond_with(resource, _opts = {})
    if resource.persisted?
      render json: {
        token: resource.generate_jwt,
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