FactoryBot.define do
  factory :subscription do
    user
    plan_type { 'premium' }
    status { 'active' }
    start_date { Time.current }
    end_date { 1.year.from_now }
  end
end