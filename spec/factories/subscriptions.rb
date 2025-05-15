# spec/factories/subscriptions.rb
FactoryBot.define do
  factory :subscription do
    user { create(:user) } # Ensure a unique user per subscription
    plan_type { 'free' }
    status { 'active' }
    start_date { Time.current }
    stripe_customer_id { nil }
    stripe_subscription_id { nil }
    end_date { nil }

    trait :premium_active do
      plan_type { 'premium' }
      status { 'active' }
      stripe_customer_id { 'cus_123' }
      stripe_subscription_id { 'sub_123' }
      end_date { 1.month.from_now }
    end

    trait :canceled_premium do
      plan_type { 'premium' }
      status { 'canceled' }
      stripe_customer_id { 'cus_123' }
      stripe_subscription_id { 'sub_123' }
      end_date { 1.month.from_now }
    end
  end
end