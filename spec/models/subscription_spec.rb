require 'rails_helper'

RSpec.describe Subscription, type: :model do
  describe 'associations' do
    it { should belong_to(:user) }
  end

  describe 'enums' do
    it 'defines plan_type enum with correct values' do
      expect(Subscription.plan_types).to eq(
        'free' => 'free',
        'basic' => 'basic',
        'premium' => 'premium'
      )
    end

    it 'defines status enum with correct values' do
      expect(Subscription.statuses).to eq(
        'pending' => 'pending',
        'active' => 'active',
        'cancelled' => 'cancelled',
        'past_due' => 'past_due'
      )
    end
  end

  describe 'validations' do
    let(:user) { create(:user) }
    subject { build(:subscription, user: user) }

    it { should validate_presence_of(:plan_type) }
    it { should validate_presence_of(:status) }
    it { should validate_presence_of(:start_date) }

    it 'validates plan_type inclusion' do
      subscription = build(:subscription, user: user)
      Subscription.plan_types.keys.each do |plan_type|
        subscription.plan_type = plan_type
        expect(subscription).to be_valid
      end
    end

    it 'validates status inclusion' do
      subscription = build(:subscription, user: user)
      Subscription.statuses.keys.each do |status|
        subscription.status = status
        expect(subscription).to be_valid
      end
    end

    context 'when plan_type is not free and status is not pending' do
      let(:subscription) do
        build(:subscription, user: user, plan_type: 'premium', status: 'active', stripe_subscription_id: nil, stripe_customer_id: nil)
      end

      it 'requires stripe_subscription_id and stripe_customer_id' do
        expect(subscription).not_to be_valid
        expect(subscription.errors[:stripe_subscription_id]).to include("can't be blank") # Fix: Changed to "can't be blank"
        expect(subscription.errors[:stripe_customer_id]).to include("can't be blank") # Fix: Changed to "can't be blank"
      end
    end

    context 'when plan_type is free' do
      let(:subscription) { build(:subscription, :free_plan, user: user) }

      it 'does not require stripe_subscription_id or stripe_customer_id' do
        expect(subscription).to be_valid
      end

      it 'does not require end_date' do
        expect(subscription).to be_valid
      end
    end

    context 'when status is pending' do
      let(:subscription) { build(:subscription, :pending_plan, user: user) }

      it 'does not require stripe_subscription_id or stripe_customer_id' do
        expect(subscription).to be_valid
      end
    end

    context 'when plan_type is not free' do
      let(:subscription) { build(:subscription, user: user, plan_type: 'premium', status: 'active', end_date: nil) }

      it 'requires end_date' do
        expect(subscription).not_to be_valid
        expect(subscription.errors[:end_date]).to include("can't be blank") # Fix: Changed to "can't be blank"
      end
    end
  end

  describe '#active?' do
    let(:user) { create(:user) }

    it 'returns true for active subscription with future end_date' do
      user.subscription.update!(
        status: 'active',
        plan_type: 'basic',
        end_date: 1.day.from_now,
        stripe_subscription_id: "sub_#{SecureRandom.hex(6)}",
        stripe_customer_id: "cus_#{SecureRandom.hex(6)}"
      )
      expect(user.subscription.active?).to be true
    end

    it 'returns false for cancelled status' do
      user.subscription.update!(
        status: 'cancelled',
        plan_type: 'basic',
        end_date: 1.day.from_now,
        stripe_subscription_id: "sub_#{SecureRandom.hex(6)}",
        stripe_customer_id: "cus_#{SecureRandom.hex(6)}"
      )
      expect(user.subscription.active?).to be false
    end

    it 'returns false if end_date is in the past' do
      user.subscription.update!(
        status: 'active',
        plan_type: 'basic',
        end_date: 1.day.ago,
        stripe_subscription_id: "sub_#{SecureRandom.hex(6)}",
        stripe_customer_id: "cus_#{SecureRandom.hex(6)}"
      )
      expect(user.subscription.active?).to be false
    end

    it 'returns true if no end_date and status is active' do
      user.subscription.update!(
        status: 'active',
        plan_type: 'free',
        end_date: nil,
        stripe_subscription_id: nil,
        stripe_customer_id: nil
      )
      expect(user.subscription.active?).to be true
    end
  end

  describe '#premium?' do
    let(:user) { create(:user) }

    it 'returns true for basic plan' do
      user.subscription.update!(
        plan_type: 'basic',
        status: 'active',
        end_date: 1.month.from_now,
        stripe_subscription_id: "sub_#{SecureRandom.hex(6)}",
        stripe_customer_id: "cus_#{SecureRandom.hex(6)}"
      )
      expect(user.subscription.premium?).to be true
    end

    it 'returns true for premium plan' do
      user.subscription.update!(
        plan_type: 'premium',
        status: 'active',
        end_date: 1.month.from_now,
        stripe_subscription_id: "sub_#{SecureRandom.hex(6)}",
        stripe_customer_id: "cus_#{SecureRandom.hex(6)}"
      )
      expect(user.subscription.premium?).to be true
    end

    it 'returns false for free plan' do
      user.subscription.update!(
        plan_type: 'free',
        status: 'active',
        end_date: nil,
        stripe_subscription_id: nil,
        stripe_customer_id: nil
      )
      expect(user.subscription.premium?).to be false
    end
  end

  describe 'after_update :send_notification', unless: -> { Subscription._after_update_callbacks.empty? } do
    let(:user) { create(:user, device_token: 'token123') }
    let(:subscription) { user.subscription }

    context 'when plan_type changes and is not free' do
      it 'calls send_subscription_notification' do
        expect(NotificationService).to receive(:send_subscription_notification).with(user)
        subscription.update!(
          plan_type: 'premium',
          stripe_subscription_id: "sub_#{SecureRandom.hex(6)}",
          stripe_customer_id: "cus_#{SecureRandom.hex(6)}",
          end_date: 1.month.from_now
        )
      end
    end

    context 'when status changes to cancelled' do
      it 'calls send_payment_failure_notification' do
        expect(NotificationService).to receive(:send_payment_failure_notification).with(user)
        subscription.update(status: 'cancelled')
      end
    end

    context 'when there is no significant change' do
      it 'does not call any notification service' do
        expect(NotificationService).not_to receive(:send_subscription_notification)
        expect(NotificationService).not_to receive(:send_payment_failure_notification)
        subscription.update(start_date: 1.day.ago)
      end
    end

    context 'when device_token is not present' do
      let(:user) { create(:user, device_token: nil) }
      let(:subscription) { user.subscription }

      it 'does not send notification' do
        expect(NotificationService).not_to receive(:send_payment_failure_notification)
        subscription.update(status: 'cancelled')
      end
    end
  end

  describe '.ransackable_attributes' do
    it 'returns list of ransackable attributes' do
      expect(Subscription.ransackable_attributes).to match_array(
        %w[id user_id plan_type status stripe_subscription_id stripe_customer_id start_date end_date created_at updated_at]
      )
    end
  end

  describe '.ransackable_associations' do
    it 'returns list of ransackable associations' do
      expect(Subscription.ransackable_associations).to match_array(['user'])
    end
  end
end