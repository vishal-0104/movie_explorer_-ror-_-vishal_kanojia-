FactoryBot.define do
  factory :blacklisted_token do
    association :user
    jti { SecureRandom.uuid }
    expires_at { 1.day.from_now }
  end
end
