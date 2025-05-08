FactoryBot.define do
  factory :blacklisted_token do
    token { "MyString" }
    user { nil }
  end
end
