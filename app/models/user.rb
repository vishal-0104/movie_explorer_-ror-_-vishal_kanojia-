class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :validatable,
         :jwt_authenticatable, jwt_revocation_strategy: BlacklistedToken

  enum role: { user: 0, supervisor: 1 }

  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :mobile_number, presence: true, uniqueness: true, length: { minimum: 10, maximum: 15 } # Relaxed for international formats
  validates :device_token, uniqueness: true, allow_nil: true
  before_save { self.email = email.downcase }

  has_many :blacklisted_tokens, dependent: :destroy
  has_one :subscription, dependent: :destroy
  after_create :create_default_subscription

  def self.jwt_revoked?(jwt_payload, user)
    return false if jwt_payload.nil? || jwt_payload['jti'].nil?

    blacklisted_token = BlacklistedToken.find_by(jti: jwt_payload['jti'], user_id: user.id)
    return false unless blacklisted_token

    if blacklisted_token.expires_at < Time.current
      blacklisted_token.destroy
      return false
    end

    true
  end

  def self.revoke_jwt(jwt_payload, user)
    jti = jwt_payload['jti']
    return if jti.nil? || BlacklistedToken.exists?(jti: jti)

    BlacklistedToken.create!(
      jti: jti,
      user_id: user.id,
      expires_at: Time.at(jwt_payload['exp'])
    )
  rescue StandardError => e
    Rails.logger.error "[JWT Revoke] Error for user #{user.id}: #{e.message}"
    raise
  end

  def generate_jwt
    expiration_duration = ENV['JWT_EXPIRATION_TIME']&.to_i || 24.hours.to_i
    expiration_time = Time.now.to_i + expiration_duration
    payload = { user_id: id, role: role, jti: SecureRandom.uuid, exp: expiration_time }
    JWT.encode(payload, ENV['JWT_SECRET'], 'HS256')
  end

  def token_blacklisted?(jti)
    blacklisted_tokens.exists?(jti: jti)
  end

  def self.authenticate(email, password)
    user = find_by(email: email&.downcase&.strip)
    user&.valid_password?(password) ? user : nil
  rescue StandardError => e
    Rails.logger.error "[Authentication] Error for email #{email}: #{e.message}"
    nil
  end

  def supervisor?
    role == 'supervisor'
  end

  def common_user?
    role == 'user'
  end

  def premium?
    subscription&.active? && subscription.plan_type.in?(%w[basic premium])
  end

  def can_access_premium_movies?
    premium?
  end

  def update_device_token(token)
    return if token == device_token

    update(device_token: token&.strip.presence)
  end

  def self.with_active_subscription
    joins(:subscription).where(subscriptions: { status: 'active' })
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id email role created_at updated_at first_name last_name mobile_number]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[blacklisted_tokens subscription]
  end

  private

  def create_default_subscription
    return if subscription

    build_subscription(
      plan_type: 'free',
      status: 'active',
      start_date: Time.current
    ).save
  rescue StandardError => e
    Rails.logger.error "[Default Subscription] Error for user #{id}: #{e.message}"
  end
end