require 'rails_helper'

RSpec.describe User, type: :model do
  it 'is valid with valid attributes' do
    user = build(:user)
    expect(user).to be_valid
  end

  it 'creates default subscription after creation' do
    user = create(:user)
    expect(user.subscription).to be_present
    expect(user.subscription.plan_type).to eq('free')
  end
end