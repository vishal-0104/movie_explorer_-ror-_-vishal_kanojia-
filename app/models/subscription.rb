# app/models/subscription.rb
class Subscription < ApplicationRecord
  belongs_to :user
  validates :plan_type, :status, :start_date, presence: true
  validates :stripe_subscription_id, presence: true, unless: -> { plan_type == 'free' }
  enum plan_type: { free: 'free', basic: 'basic', premium: 'premium' }
  enum status: { active: 'active', canceled: 'canceled' }

  def premium?
    plan_type == 'premium'
  end

  def active?
    status == 'active'
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id user_id plan_type status stripe_subscription_id start_date end_date created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[user]
  end

  after_update :send_notification, if: -> { saved_change_to_plan_type? && plan_type != 'free' }

  private

  def send_notification
    return unless user.device_token.present?

    FCMService.send_notification(
      user.device_token,
      title: 'Subscription Updated!',
      body: "Your #{plan_type} plan is now active.",
      data: { subscription_id: id.to_s }
    )
  end
end