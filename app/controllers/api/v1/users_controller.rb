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

  def update_profile_picture
  if params[:profile_picture].blank?
    render json: { errors: ["Profile picture is required"] }, status: :unprocessable_entity
    return
  end

  begin
    @current_user.profile_picture.attach(params[:profile_picture])
    if @current_user.save
      if @current_user.profile_picture.attached?
        render json: { message: "Profile picture updated", profile_picture_url: url_for(@current_user.profile_picture) }, status: :ok
      else
        render json: { errors: @current_user.errors.full_messages }, status: :unprocessable_entity
      end
    else
      render json: { errors: @current_user.errors.full_messages }, status: :unprocessable_entity
    end
  rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError => e
    Rails.logger.error("Profile picture upload failed: #{e.message}")
    render json: { errors: ["Failed to process profile picture. Ensure it's a valid image file."] }, status: :unprocessable_entity
  end
  end

  def show_profile_picture
    if @current_user.profile_picture.attached?
      render json: { profile_picture_url: url_for(@current_user.profile_picture) }, status: :ok
    else
      render json: { errors: ["No profile picture found"] }, status: :not_found
    end
  end
end
