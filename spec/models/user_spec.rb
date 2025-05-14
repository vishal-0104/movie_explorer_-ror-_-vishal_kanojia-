require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'associations' do
    it { should have_one(:subscription).dependent(:destroy) }
  end

  describe 'enums' do
    it { should define_enum_for(:role).with_values(user: 0, supervisor: 1) }
  end

  describe 'validations' do
    subject { create(:user) }

    it { should validate_presence_of(:first_name) }
    it { should validate_length_of(:first_name).is_at_most(100) }

    it { should validate_presence_of(:last_name) }
    it { should validate_length_of(:last_name).is_at_most(100) }

    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email).case_insensitive }
    it { should allow_value('test@example.com').for(:email) }

    it { should validate_presence_of(:mobile_number) }
    it { should validate_uniqueness_of(:mobile_number).case_insensitive }
    it { should allow_value('+12345678901').for(:mobile_number) }
    it { should_not allow_value('12345').for(:mobile_number) }

    it { should validate_uniqueness_of(:device_token).allow_nil }
    it { should validate_presence_of(:jti) }
    it { should validate_uniqueness_of(:jti) }
  end

  describe 'callbacks' do
    it 'downcases the email before save' do
      user = create(:user, email: 'Test@Email.com')
      expect(user.email).to eq('test@email.com')
    end

    it 'creates a default subscription after creation' do
      user = create(:user)
      expect(user.subscription).to be_present
      expect(user.subscription.plan_type).to eq('free')
      expect(user.subscription.status).to eq('active')
    end
  end

  describe 'scopes' do
    let!(:active_user) do
      create(:user).tap do |user|
        user.subscription.update!(
          plan_type: 'premium',
          status: 'active',
          end_date: 2.days.from_now,
          stripe_customer_id: 'cus_123',
          stripe_subscription_id: 'sub_123'
        )
      end
    end

    let!(:inactive_user) do
      create(:user).tap do |user|
        user.subscription.update!(
          plan_type: 'premium',
          status: 'canceled',
          end_date: 1.day.ago,
          stripe_customer_id: 'cus_456',
          stripe_subscription_id: 'sub_456'
        )
      end
    end

    it '.with_active_subscription returns only users with active subscriptions' do
      result = User.with_active_subscription
      expect(result).to include(active_user)
      expect(result).not_to include(inactive_user)
    end
  end

  describe 'instance methods' do
    let(:user) { create(:user) }

    describe '#supervisor?' do
      it 'returns true for supervisor role' do
        user.update!(role: :supervisor)
        expect(user.supervisor?).to be true
      end
    end

    describe '#common_user?' do
      it 'returns true for user role' do
        user.update!(role: :user)
        expect(user.common_user?).to be true
      end
    end

    describe '#premium?' do
      it 'returns true if subscription is active and premium' do
        user.subscription.update!(
          plan_type: 'premium',
          status: 'active',
          end_date: 1.month.from_now,
          stripe_customer_id: 'cus_abc',
          stripe_subscription_id: 'sub_abc'
        )
        expect(user.premium?).to be true
      end

      it 'returns false for canceled subscription' do
        user.subscription.update!(
          plan_type: 'premium',
          status: 'canceled',
          end_date: 1.month.from_now,
          stripe_customer_id: 'cus_def',
          stripe_subscription_id: 'sub_def'
        )
        expect(user.premium?).to be false
      end

      it 'returns false for free plan' do
        user.subscription.update!(plan_type: 'free', status: 'active')
        expect(user.premium?).to be false
      end
    end

    describe '#can_access_premium_movies?' do
      it 'delegates to #premium?' do
        allow(user).to receive(:premium?).and_return(true)
        expect(user.can_access_premium_movies?).to be true
      end
    end

    describe '#jwt_payload' do
      it 'includes expected keys in the payload' do
        payload = user.jwt_payload
        expect(payload).to include(:role, :user_id, :scp)
        expect(payload[:scp]).to eq('api_v1_user')
      end
    end
  end

  describe '.ransackable_attributes' do
    it 'includes searchable attributes' do
      expect(User.ransackable_attributes).to include('email', 'role', 'mobile_number')
    end
  end

  describe '.ransackable_associations' do
    it 'includes searchable associations' do
      expect(User.ransackable_associations).to include('subscription')
    end
  end
end
