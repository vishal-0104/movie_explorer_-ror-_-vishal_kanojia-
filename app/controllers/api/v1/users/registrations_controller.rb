class Api::V1::Users::RegistrationsController < Devise::RegistrationsController
  skip_before_action :verify_authenticity_token
  respond_to :json

  def create
    build_resource(sign_up_params)
    resource.jti = SecureRandom.uuid
    if resource.save
      sign_in(resource_name, resource)
      token = Warden::JWTAuth::UserEncoder.new.call(resource, :user, nil)
      request.env['warden-jwt_auth.token'] = token
      send_whatsapp_opt_in_sms(resource) if resource.mobile_number
      respond_with(resource)
    else
      respond_with(resource)
    end
  end

  private

  def sign_up_params
    params.require(:user).permit(:email, :password, :first_name, :last_name, :mobile_number, :role)
  end

  def respond_with(resource, _opts = {})
    if resource.persisted?
      render json: {
        token: request.env['warden-jwt_auth.token'],
        user: user_response(resource),
        whatsapp_opt_in_required: resource.mobile_number.present?
      }, status: :created
    else
      render json: { error: 'Unprocessable Entity', errors: resource.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def user_response(user)
    user.as_json(only: [:id, :email, :first_name, :last_name, :mobile_number, :role, :created_at, :updated_at])
  end

  def send_whatsapp_opt_in_sms(user)
    client = Twilio::REST::Client.new(ENV['TWILIO_ACCOUNT_SID'], ENV['TWILIO_AUTH_TOKEN'])
    join_link = 'https://wa.me/+14155238886?text=join%20welcome-coat'
    message = "Welcome to YourApp! Enable WhatsApp notifications by clicking: #{join_link}"
    client.messages.create(
      from: ENV['TWILIO_PHONE_NUMBER'],
      to: user.mobile_number,
      body: message
    )
    Rails.logger.info("Sent WhatsApp opt-in SMS to #{user.mobile_number}")
  rescue Twilio::REST::RestError => e
    Rails.logger.error("Failed to send WhatsApp opt-in SMS to #{user.mobile_number}: #{e.message} (Code: #{e.code})")
  end
end