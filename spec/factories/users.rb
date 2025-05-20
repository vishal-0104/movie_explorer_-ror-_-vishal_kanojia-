FactoryBot.define do
  factory :user do
    first_name { "John" }
    last_name  { "Doe" }
    email { Faker::Internet.unique.email }
    password { "Password123" }
    password_confirmation { "Password123" }
    mobile_number { Faker::Number.number(digits: 10).to_s }
    role { :user }
    jti { SecureRandom.uuid }
    device_token { nil }
    
    trait :without_subscription do
      after(:create) do |user|
        user.subscription.destroy if user.subscription
      end
    end
    
  end
end
