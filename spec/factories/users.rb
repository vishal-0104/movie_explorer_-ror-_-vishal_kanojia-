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

    # No subscription created here to let callback handle it
  end
end
