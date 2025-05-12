FactoryBot.define do
  factory :user do
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    email { Faker::Internet.email }
    mobile_number { Faker::Number.number(digits: 10) }
    password { 'password123' }
    role { 'user' }
    # Remove the after(:create) callback
  end
end