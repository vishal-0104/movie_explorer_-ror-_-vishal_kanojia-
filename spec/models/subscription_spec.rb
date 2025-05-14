require 'rails_helper'

RSpec.describe Subscription, type: :model do
  describe 'associations' do
    it { should belong_to(:user) }
  end

  describe 'enums' do
    it { should define_enum_for(:plan_type).with_values(free: 'free', basic: 'basic', premium: 'premium') }
    it { should define_enum_for(:status).with_values(pending: 'pending', active: 'active', canceled: 'canceled', past_due: 'past_due') }
  end

  describe 'validations' do
    it { should validate_presence_of(:plan_type) }
    it { should validate_inclusion_of(:plan_type).in_array(%w[free basic premium]) }

    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[pending active canceled past_due]) }

    it { should validate_presence_of(:start_date) }

    context 'for free plan' do
      subject { build(:subscription, plan_type: 'free') }

      it 'allows blank stripe_customer_id and stripe_subscription_id' do
        expect(subject).to be_valid
      end

      it 'does not require end_date' do
        subject.end_date = nil
        expect(subject).to be_valid
      end
    end

    context 'for premium plan' do
      subject { build(:subscription, :premium_active) }

      it 'requires stripe fields and end_date' do
        subject.stripe_customer_id = nil
        expect(subject).not_to be_valid

        subject.stripe_customer_id = 'cus_123'
        subject.stripe_subscription_id = nil
        expect(subject).not_to be_valid

        subject.stripe_subscription_id = 'sub_123'
        subject.end_date = nil
        expect(subject).not_to be_valid

        subject.end_date = 1.month.from_now
        expect(subject).to be_valid
      end
    end
  end

  describe '#active?' do
    it 'returns true if status is active and end_date is in the future' do
      sub = build(:subscription, :premium_active)
      expect(sub.active?).to be true
    end

    it 'returns false if end_date is in the past' do
      sub = build(:subscription, :premium_active, end_date: 1.day.ago)
      expect(sub.active?).to be false
    end

    it 'returns false if status is not active' do
      sub = build(:subscription, :canceled_premium)
      expect(sub.active?).to be false
    end
  end

  describe '#premium?' do
    it 'returns true for premium or basic plan' do
      premium = build(:subscription, plan_type: 'premium')
      basic = build(:subscription, plan_type: 'basic')
      expect(premium.premium?).to be true
      expect(basic.premium?).to be true
    end

    it 'returns false for free plan' do
      sub = build(:subscription, plan_type: 'free')
      expect(sub.premium?).to be false
    end
  end

  describe 'notifications' do
    let(:user) { create(:user, device_token: 'token123') }

    before do
      allow(NotificationService).to receive(:send_subscription_notification)
      allow(NotificationService).to receive(:send_payment_failure_notification)
    end

    it 'sends notification on plan_type change to premium' do
      sub = create(:subscription, user: user, plan_type: 'free')
      sub.update(plan_type: 'premium')
      expect(NotificationService).to have_received(:send_subscription_notification).with(user, 'premium')
    end

    it 'sends payment failure notification on status change to canceled' do
      sub = create(:subscription, :premium_active, user: user)
      sub.update(status: 'canceled')
      expect(NotificationService).to have_received(:send_payment_failure_notification).with(user)
    end

    it 'does not raise error on notification failure' do
      allow(NotificationService).to receive(:send_subscription_notification).and_raise(StandardError)
      sub = create(:subscription, user: user, plan_type: 'free')
      expect {
        sub.update(plan_type: 'premium')
      }.not_to raise_error
    end
  end

  describe '.ransackable_attributes' do
    it 'returns allowed searchable attributes' do
      expect(Subscription.ransackable_attributes).to include('plan_type', 'status', 'stripe_subscription_id')
    end
  end

  describe '.ransackable_associations' do
    it 'includes user association' do
      expect(Subscription.ransackable_associations).to include('user')
    end
  end
end
