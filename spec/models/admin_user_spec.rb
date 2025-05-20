require 'rails_helper'

RSpec.describe AdminUser, type: :model do
  describe 'validations' do
    subject { build(:admin_user) }

    it 'validates presence of email' do
      subject.email = nil
      expect(subject).not_to be_valid
      expect(subject.errors[:email]).to include("can't be blank")
    end

    it 'validates uniqueness of email' do
      create(:admin_user, email: 'admin@example.com')
      new_admin = build(:admin_user, email: 'admin@example.com')
      expect(new_admin).not_to be_valid
      expect(new_admin.errors[:email]).to include('has already been taken')
    end

    it 'allows valid email format' do
      subject.email = 'admin@example.com'
      expect(subject).to be_valid
    end

    it 'rejects invalid email format' do
      subject.email = 'invalid_email'
      expect(subject).not_to be_valid
      expect(subject.errors[:email]).to include('is invalid')
    end

    it 'validates presence of password on create' do
      admin_user = build(:admin_user, password: nil, password_confirmation: nil)
      expect(admin_user).not_to be_valid
      expect(admin_user.errors[:password]).to include("can't be blank")
    end

    it 'validates password confirmation' do
      admin_user = build(:admin_user, password: 'Password123', password_confirmation: 'Different')
      expect(admin_user).not_to be_valid
      expect(admin_user.errors[:password_confirmation]).to include("doesn't match Password")
    end
  end

  describe 'devise modules' do
    let(:admin_user) { create(:admin_user, email: 'admin@example.com', password: 'Password123') }

    describe 'database_authenticatable' do
      it 'authenticates with valid credentials' do
        expect(admin_user).to be_persisted, "User not persisted: #{admin_user.errors.full_messages}"
        expect(admin_user.email).to eq('admin@example.com'), "Email mismatch: got #{admin_user.email}"
        found_user = AdminUser.find_by("lower(email) = ?", 'admin@example.com'.downcase)
        expect(found_user).to eq(admin_user), "User not found by email: #{AdminUser.all.pluck(:email)}"
        auth_user = AdminUser.find_for_authentication(email: 'admin@example.com')
        expect(auth_user).to eq(admin_user), "User not found for authentication"
        expect(auth_user.valid_password?('Password123')).to be true
      end

      it 'does not authenticate with invalid password' do
        expect(admin_user.valid_password?('WrongPassword')).to be false
      end
    end

    describe 'recoverable' do
      it 'generates a reset password token' do
        allow_any_instance_of(Devise::Mailer).to receive(:reset_password_instructions).and_return(true)
        admin_user.send_reset_password_instructions
        expect(admin_user.reset_password_token).to be_present
        expect(admin_user.reset_password_sent_at).to be_present
      end
    end
  end

  describe 'factory' do
    it 'has a valid factory' do
      admin_user = build(:admin_user)
      expect(admin_user).to be_valid, "Factory invalid: #{admin_user.errors.full_messages}"
      expect { create(:admin_user) }.not_to raise_error, "Create failed: #{admin_user.errors.full_messages}"
    end
  end

  describe '.ransackable_attributes' do
    it 'returns allowed searchable attributes' do
      expect(AdminUser.ransackable_attributes).to match_array(['id', 'email', 'created_at', 'updated_at'])
    end
  end
end