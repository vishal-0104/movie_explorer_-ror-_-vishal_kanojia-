# app/controllers/api/v1/users_controller.rb
class Api::V1::UsersController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_api_v1_user!

  def update_device_token
    if current_api_v1_user.update(device_token: params[:device_token])
      render json: { message: 'Device token updated' }, status: :ok
    else
      render json: { errors: current_api_v1_user.errors.full_messages }, status: :unprocessable_entity
    end
  end
end