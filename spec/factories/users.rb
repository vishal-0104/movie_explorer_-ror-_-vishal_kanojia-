FactoryBot.define do
  factory :user do
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    email { Faker::Internet.email }
    mobile_number { Faker::PhoneNumber.subscriber_number(length: 10) }
    password { 'password' }
    role { :user }
  end

  factory :supervisor, class: 'User' do
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    email { Faker::Internet.email }
    mobile_number { Faker::PhoneNumber.subscriber_number(length: 10) }
    password { 'password' }
    role { :supervisor }
  end
end