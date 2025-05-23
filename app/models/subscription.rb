class Subscription < ApplicationRecord
  belongs_to :user

  enum plan_type: { free: 'free', basic: 'basic', premium: 'premium' }
  enum status: { pending: 'pending', active: 'active', cancelled: 'cancelled', past_due: 'past_due' }

  validates :plan_type, presence: true, inclusion: { in: plan_types.keys }
  validates :status, presence: true, inclusion: { in: statuses.keys }
  validates :start_date, presence: true
  validates :stripe_subscription_id, presence: true, unless: -> { plan_type == 'free' || status == 'pending' }
  validates :stripe_customer_id, presence: true, unless: -> { plan_type == 'free' || status == 'pending' }
  validates :end_date, presence: true, if: -> { plan_type != 'free' }

  def active?
    status == 'active' && (end_date.nil? || end_date > Time.current)
  end

  def premium?
    plan_type.in?(%w[basic premium])
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id user_id plan_type status stripe_subscription_id stripe_customer_id start_date end_date created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[user]
  end
end