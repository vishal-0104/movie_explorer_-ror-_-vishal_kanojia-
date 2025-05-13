require 'rails_helper'
require 'jwt'
include ActiveSupport::Testing::TimeHelpers

RSpec.describe User, type: :model do
  let(:user) { create(:user) }

  describe 'validations' do
    subject { build(:user, first_name: 'John', last_name: 'Doe', email: 'test@example.com', mobile_number: '1234567890') }
  
    it { should validate_presence_of(:first_name) }
    it { should validate_presence_of(:last_name) }
    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email).case_insensitive }
    it { should validate_presence_of(:mobile_number) }
    it { should validate_uniqueness_of(:mobile_number).case_insensitive } # Add case_insensitive
    it { should validate_length_of(:mobile_number).is_equal_to(10) }
    it { should allow_value(nil).for(:device_token) }
  end

  describe 'associations' do
    it { should have_many(:blacklisted_tokens).dependent(:destroy) }
    it { should have_one(:subscription).dependent(:destroy) }
  end

  describe 'enums' do
    it { should define_enum_for(:role).with_values(user: 0, supervisor: 1) }
  end

  describe 'callbacks' do
    it 'downcases email before save' do
      user = build(:user, email: "Test@Example.com")
      user.save
      expect(user.email).to eq("test@example.com")
    end

    it 'creates a default subscription after create' do
      new_user = create(:user)
      expect(new_user.subscription).to be_present
      expect(new_user.subscription.plan_type).to eq("free")
    end
  end

  describe '.authenticate' do
    it 'returns user if valid credentials' do
      expect(User.authenticate(user.email, user.password)).to eq(user)
    end

    it 'returns nil if password is wrong' do
      expect(User.authenticate(user.email, 'wrongpass')).to be_nil
    end

    it 'returns nil if email is missing' do
      expect(User.authenticate(nil, user.password)).to be_nil
    end
  end

  describe '#generate_jwt' do
    it 'returns a valid JWT token' do
      travel_to Time.current do
        ENV['JWT_SECRET'] = 'secret'
        ENV['JWT_EXPIRATION_TIME'] = '86400'

        token = user.generate_jwt
        decoded = JWT.decode(token, ENV['JWT_SECRET'], true, algorithm: 'HS256')

        expect(decoded.first['user_id']).to eq(user.id)
        expect(decoded.first['role']).to eq(user.role)
        expect(decoded.first['exp']).to eq((Time.now.to_i + 86400))
      end
    end
  end

  describe '.jwt_revoked?' do
    it 'returns false if jti is nil' do
      expect(User.jwt_revoked?({}, user)).to be_falsey
    end

    it 'returns true if token is blacklisted and not expired' do
      token = create(:blacklisted_token, user: user)
      expect(User.jwt_revoked?({ 'jti' => token.jti }, user)).to be_truthy
    end

    it 'removes expired token and returns false' do
      token = create(:blacklisted_token, user: user, expires_at: 1.minute.ago)
      expect(User.jwt_revoked?({ 'jti' => token.jti }, user)).to be_falsey
      expect(BlacklistedToken.find_by(id: token.id)).to be_nil
    end
  end

  describe '.revoke_jwt' do
    it 'creates a blacklisted token if not exists' do
      payload = { 'jti' => SecureRandom.uuid, 'exp' => 2.hours.from_now.to_i }
      expect {
        User.revoke_jwt(payload, user)
      }.to change { BlacklistedToken.count }.by(1)
    end

    it 'does not create duplicate token' do
      payload = { 'jti' => 'abc123', 'exp' => 2.hours.from_now.to_i }
      create(:blacklisted_token, jti: 'abc123', user: user)
      expect {
        User.revoke_jwt(payload, user)
      }.not_to change { BlacklistedToken.count }
    end
  end

  describe '#supervisor?' do
    it 'returns true for supervisor' do
      user.supervisor!
      expect(user.supervisor?).to be true
    end
  end

  describe '#common_user?' do
    it 'returns true for user' do
      expect(user.common_user?).to be true
    end
  end

  describe '#premium?' do
    it 'returns false if no active premium or basic subscription' do
      user.subscription.update(plan_type: 'free')
      expect(user.premium?).to be false
    end

    it 'returns true for premium plan' do
      user.subscription.update(plan_type: 'premium')
      expect(user.premium?).to be true
    end
  end

  describe '#can_access_premium_movies?' do
    it 'returns true if premium user' do
      user.subscription.update(plan_type: 'premium')
      expect(user.can_access_premium_movies?).to be true
    end
  end

  describe '.ransackable_attributes' do
    it 'returns allowed attributes' do
      expect(User.ransackable_attributes).to include('email', 'role', 'first_name')
    end
  end

  describe '.ransackable_associations' do
    it 'returns allowed associations' do
      expect(User.ransackable_associations).to include('blacklisted_tokens', 'subscription')
    end
  end
end
