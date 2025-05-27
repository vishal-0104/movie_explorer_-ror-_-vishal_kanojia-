require 'rails_helper'

RSpec.describe BlacklistedToken, type: :model do
  let(:user) { create(:user) }
  let(:payload) { { 'jti' => 'unique_jti', 'user_id' => user.id } }
  subject { build(:blacklisted_token, user: user) }

  describe 'validations' do
    it { should validate_presence_of(:jti) }
    it { should validate_uniqueness_of(:jti) }
    it { should validate_presence_of(:expires_at) }
  end

  describe 'associations' do
    it { should belong_to(:user) }
  end

  describe 'factory' do
    it 'has a valid factory' do
      expect(subject).to be_valid
    end
  end

  describe 'when jti is missing' do
    it 'is not valid' do
      subject.jti = nil
      expect(subject).not_to be_valid
      expect(subject.errors[:jti]).to include("can't be blank")
    end
  end

  describe 'when expires_at is missing' do
    it 'is not valid' do
      subject.expires_at = nil
      expect(subject).not_to be_valid
      expect(subject.errors[:expires_at]).to include("can't be blank")
    end
  end

  describe 'when jti is not unique' do
    it 'is not valid' do
      create(:blacklisted_token, jti: subject.jti, user: user)
      expect(subject).not_to be_valid
      expect(subject.errors[:jti]).to include('has already been taken')
    end
  end

  describe '.revoked?' do
    it 'returns false if jti is nil' do
      expect(BlacklistedToken.revoked?({ 'jti' => nil, 'user_id' => user.id })).to be false
    end

    it 'returns false if token is not found' do
      expect(BlacklistedToken.revoked?(payload)).to be false
    end

    it 'returns true if token exists and is not expired' do
      create(:blacklisted_token, jti: 'unique_jti', user: user, expires_at: 1.hour.from_now)
      expect(BlacklistedToken.revoked?(payload)).to be true
    end

    it 'returns false and destroys token if token is expired' do
      blacklisted_token = create(:blacklisted_token, jti: 'unique_jti', user: user, expires_at: 1.hour.ago)
      expect(BlacklistedToken.revoked?(payload)).to be false
      expect(BlacklistedToken.find_by(jti: 'unique_jti')).to be_nil
    end
  end

  describe '.revoke' do
    it 'creates a blacklisted token if user exists' do
      # Temporary stub until devise-jwt is configured
      allow(user).to receive(:revoke_jwt)
      expect(user).to receive(:revoke_jwt).with(payload, user) # Keep expectation
      BlacklistedToken.revoke(payload)
      expect(BlacklistedToken.find_by(jti: 'unique_jti', user_id: user.id)).to be_present
    end

    it 'does not create a token if jti is nil' do
      BlacklistedToken.revoke('jti' => nil, 'user_id' => user.id)
      expect(BlacklistedToken.count).to eq(0)
    end

    it 'does not create a token if user_id is nil' do
      BlacklistedToken.revoke('jti' => 'unique_jti', 'user_id' => nil)
      expect(BlacklistedToken.count).to eq(0)
    end

    it 'does not create a duplicate token' do
      create(:blacklisted_token, jti: 'unique_jti', user: user)
      allow(user).to receive(:revoke_jwt) # Stub for duplicate test
      BlacklistedToken.revoke(payload)
      expect(BlacklistedToken.where(jti: 'unique_jti').count).to eq(1)
    end

    it 'raises an error if user is not found' do
      expect {
        BlacklistedToken.revoke('jti' => 'unique_jti', 'user_id' => 999)
      }.to raise_error(ActiveRecord::RecordNotFound, /User not found/)
    end

    it 'does not create a token if payload is invalid' do
      BlacklistedToken.revoke({})
      expect(BlacklistedToken.count).to eq(0)
    end
  end

  describe '.cleanup_expired' do
    it 'destroys expired tokens' do
      create(:blacklisted_token, user: user, expires_at: 1.hour.ago)
      create(:blacklisted_token, user: user, expires_at: 1.hour.from_now)
      BlacklistedToken.cleanup_expired
      expect(BlacklistedToken.count).to eq(1)
      expect(BlacklistedToken.first.expires_at).to be > Time.current
    end
  end
end