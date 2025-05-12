require 'rails_helper'

RSpec.describe BlacklistedToken, type: :model do
  let(:user) { create(:user) }

  subject do
    build(:blacklisted_token, user: user)
  end

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

  context 'when jti is missing' do
    it 'is not valid' do
      subject.jti = nil
      expect(subject).to_not be_valid
    end
  end

  context 'when expires_at is missing' do
    it 'is not valid' do
      subject.expires_at = nil
      expect(subject).to_not be_valid
    end
  end

  context 'when jti is not unique' do
    it 'is not valid' do
      create(:blacklisted_token, jti: subject.jti)
      expect(subject).to_not be_valid
    end
  end
end
