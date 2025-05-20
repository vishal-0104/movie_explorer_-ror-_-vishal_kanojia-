FactoryBot.define do
  factory :subscription do
    association :user
    plan_type { 'basic' }
    status { 'active' }
    start_date { Time.current }
    end_date { 1.month.from_now }


    stripe_subscription_id { "sub_#{SecureRandom.hex(6)}" }
    stripe_customer_id { "cus_#{SecureRandom.hex(6)}" }

    trait :free_plan do
      plan_type { 'free' }
      status { 'active' }
      stripe_subscription_id { nil }
      stripe_customer_id { nil }
      end_date { nil }
    end

    trait :pending_plan do
      plan_type { 'basic' }
      status { 'pending' }
      stripe_subscription_id { nil }
      stripe_customer_id { nil }
      end_date { 1.month.from_now }
    end
  end
end
