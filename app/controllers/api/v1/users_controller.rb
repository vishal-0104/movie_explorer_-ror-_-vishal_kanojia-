class Api::V1::UsersController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_api_v1_user!

  def update_device_token
    device_token = params[:device_token]


    unless device_token&.match?(/\A[a-zA-Z0-9:_\-\.]{100,200}\z/)
      Rails.logger.warn("Invalid device token received: #{device_token}")
      render json: { errors: [ "Device token is invalid. Must be a valid FCM registration token." ] }, status: :unprocessable_entity
      return
    end

    if @current_user.update(device_token: device_token)
      render json: { message: "Device token updated" }, status: :ok
    else
      render json: { errors: @current_user.errors.full_messages }, status: :unprocessable_entity
    end
  end
end
