# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :rememberable, :validatable,
         :jwt_authenticatable, jwt_revocation_strategy: self

  enum role: { user: 0, supervisor: 1 }

  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :mobile_number, presence: true, uniqueness: true, length: { is: 10 }
  validates :device_token, uniqueness: true, allow_nil: true
  before_save { self.email = email.downcase }

  has_many :blacklisted_tokens, dependent: :destroy
  has_one :subscription, dependent: :destroy
  after_create :create_default_subscription

  def self.jwt_revoked?(jwt_payload, user)
    BlacklistedToken.exists?(token: jwt_payload['jti'], user_id: user.id)
  end

  def self.revoke_jwt(jwt_payload, user)
    BlacklistedToken.create!(token: jwt_payload['jti'], user_id: user.id)
  end

  def generate_jwt
    payload = { user_id: id, role: role, jti: SecureRandom.uuid, exp: 24.hours.from_now.to_i }
    JWT.encode(payload, ENV['JWT_SECRET'], 'HS256')
  end

  def token_blacklisted?(token)
    blacklisted_tokens.exists?(token: token)
  end

  def self.authenticate(email, password)
    return nil if email.blank? || password.blank?
    user = find_by(email: email.downcase.strip)
    user if user&.valid_password?(password)
  end

  def supervisor?
    role == 'supervisor'
  end

  def common_user?
    role == 'user'
  end

  def premium?
    subscription&.active? && %w[basic premium].include?(subscription&.plan_type)
  end

  def can_access_premium_movies?
    premium?
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id email role created_at updated_at first_name last_name mobile_number]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[blacklisted_tokens subscription]
  end

  private

  def create_default_subscription
    build_subscription(plan_type: :free, status: :active, start_date: Time.current).save! unless subscription
  end
end