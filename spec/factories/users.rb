FactoryBot.define do
  factory :user do
    first_name { 'John' }
    last_name { 'Doe' }
    email { Faker::Internet.email }
    sequence(:mobile_number) { |n| "+123456789#{format('%02d', n)}" } # Generates +12345678901, +12345678902, etc.
    jti { SecureRandom.uuid }
    password { 'password123' }

    trait :without_subscription do
      after(:create) do |user|
        user.subscription.destroy if user.subscription
      end
    end
  end
end