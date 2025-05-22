class User < ApplicationRecord
  include Devise::JWT::RevocationStrategies::JTIMatcher
  devise :database_authenticatable, :registerable, :validatable,
         :jwt_authenticatable, jwt_revocation_strategy: self

  enum role: { user: 0, supervisor: 1 }

  validates :first_name, presence: true, length: { maximum: 100 }
  validates :last_name, presence: true, length: { maximum: 100 }
  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :mobile_number, presence: true, uniqueness: true, format: { with: /\A(\+?[1-9]\d{0,3})?\d{9,14}\z/ }
  validates :device_token, uniqueness: true, allow_nil: true
  validates :jti, presence: true, uniqueness: true
  validates :profile_picture, content_type: ['image/png', 'image/jpeg'], size: { less_than: 5.megabytes }, allow_nil: true
  before_save { self.email = email.downcase }

  has_one_attached :profile_picture
  has_one :subscription, dependent: :destroy
  after_create :create_default_subscription

  scope :with_active_subscription, -> {
    joins(:subscription)
      .where(subscriptions: { status: 'active' })
      .where('subscriptions.end_date IS NULL OR subscriptions.end_date > ?', Time.current)
  }

  def jwt_payload
    { role: role, user_id: id, scp: 'api_v1_user' }
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
    %w[subscription]
  end

  private

  def create_default_subscription
    return if subscription
    Subscription.create!(
      user: self,
      plan_type: 'free',
      status: 'active',
      start_date: Time.current
    )
  end
end