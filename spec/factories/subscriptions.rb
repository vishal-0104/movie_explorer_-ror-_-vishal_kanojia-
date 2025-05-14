FactoryBot.define do
  factory :subscription do
    user
    plan_type { 'free' }
    status { 'active' }
    start_date { Time.current }
    end_date { plan_type == 'free' ? nil : 1.year.from_now }

    stripe_customer_id { plan_type == 'free' ? nil : "cus_#{SecureRandom.hex(8)}" }
    stripe_subscription_id { plan_type == 'free' ? nil : "sub_#{SecureRandom.hex(8)}" }

    trait :premium_active do
      plan_type { 'premium' }
      status { 'active' }
      end_date { 1.year.from_now }
      stripe_customer_id { "cus_#{SecureRandom.hex(8)}" }
      stripe_subscription_id { "sub_#{SecureRandom.hex(8)}" }
    end

    trait :canceled_premium do
      plan_type { 'premium' }
      status { 'canceled' }
      end_date { 1.month.ago }
      stripe_customer_id { "cus_#{SecureRandom.hex(8)}" }
      stripe_subscription_id { "sub_#{SecureRandom.hex(8)}" }
    end
  end
end
