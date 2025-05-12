# spec/factories/subscriptions.rb
FactoryBot.define do
  factory :subscription do
    plan_type { :free }
    status    { :active }
    start_date { Time.current }
    user
  end
end
