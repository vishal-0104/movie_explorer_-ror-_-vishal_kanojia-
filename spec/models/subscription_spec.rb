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
        'canceled' => 'canceled',
        'past_due' => 'past_due'
      )
    end
  end

  describe 'validations' do
    let(:user) { create(:user) }
    subject { build(:subscription, user: user) }

    it { should validate_presence_of(:plan_type) }
    it { should validate_presence_of(:start_date) }

    it 'validates plan_type inclusion' do
      subscription = build(:subscription, user: user, plan_type: 'basic')
      expect(subscription).to be_valid

      inclusion_validator = Subscription.validators_on(:plan_type).find do |v|
        v.is_a?(ActiveModel::Validations::InclusionValidator)
      end
      expect(inclusion_validator).to be_present, 'Inclusion validator for plan_type not found'
      expect(inclusion_validator.options[:in]).to match_array(Subscription.plan_types.keys)
    end

    it 'validates status inclusion' do
      subscription = build(:subscription, user: user, status: 'active')
      expect(subscription).to be_valid

      inclusion_validator = Subscription.validators_on(:status).find do |v|
        v.is_a?(ActiveModel::Validations::InclusionValidator)
      end
      expect(inclusion_validator).to be_present, 'Inclusion validator for status not found'
      expect(inclusion_validator.options[:in]).to match_array(Subscription.statuses.keys)
    end

    context 'when plan_type is not free and status is not pending' do
      let(:subscription) do
        build(:subscription, user: user, plan_type: 'basic', status: 'active', stripe_subscription_id: nil, stripe_customer_id: nil)
      end

      it 'requires stripe_subscription_id and stripe_customer_id' do
        expect(subscription).to be_invalid
        expect(subscription.errors[:stripe_subscription_id]).to include("can't be blank")
        expect(subscription.errors[:stripe_customer_id]).to include("can't be blank")
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
      let(:subscription) { build(:subscription, user: user, plan_type: 'premium', end_date: nil) }

      it 'requires end_date' do
        expect(subscription).to be_invalid
        expect(subscription.errors[:end_date]).to include("can't be blank")
      end
    end
  end

  describe '#active?' do
    let(:user) { create(:user) }

    it 'returns true for active subscription with future end_date' do
      subscription = build(:subscription, user: user, status: 'active', end_date: 1.day.from_now)
      expect(subscription.active?).to eq(true)
    end

    it 'returns false for canceled status' do
      subscription = build(:subscription, user: user, status: 'canceled')
      expect(subscription.active?).to eq(false)
    end

    it 'returns false if end_date is in the past' do
      subscription = build(:subscription, user: user, status: 'active', end_date: 1.day.ago)
      expect(subscription.active?).to eq(false)
    end

    it 'returns true if no end_date and status is active' do
      subscription = build(:subscription, user: user, status: 'active', end_date: nil)
      expect(subscription.active?).to eq(true)
    end
  end

  describe '#premium?' do
    let(:user) { create(:user) }

    it 'returns true for basic plan' do
      subscription = build(:subscription, user: user, plan_type: 'basic')
      expect(subscription.premium?).to eq(true)
    end

    it 'returns true for premium plan' do
      subscription = build(:subscription, user: user, plan_type: 'premium')
      expect(subscription.premium?).to eq(true)
    end

    it 'returns false for free plan' do
      subscription = build(:subscription, user: user, plan_type: 'free')
      expect(subscription.premium?).to eq(false)
    end
  end

  describe 'after_update :send_notification' do
    context 'when plan_type changes and is not free' do
      let(:user) { create(:user, device_token: 'token123') }

      before do
        Subscription.where(user: user).destroy_all
        @subscription = create(:subscription, :free_plan, user: user)
      end

      it 'does not call send_subscription_notification if conditions are not met' do
        expect(NotificationService).not_to receive(:send_subscription_notification)

        @subscription.update(plan_type: 'basic')
      end
    end

    context 'when status changes to canceled' do
      let(:user) { create(:user, device_token: 'token123') }

      before do
        Subscription.where(user: user).destroy_all
        @subscription = create(:subscription, user: user, status: 'active')
      end

      it 'calls send_payment_failure_notification' do
        expect(NotificationService).to receive(:send_payment_failure_notification)
          .with(user)

        @subscription.update(status: 'canceled')
      end
    end

    context 'when there is no significant change' do
      let(:user) { create(:user, device_token: 'token123') }

      before do
        Subscription.where(user: user).destroy_all
        @subscription = create(:subscription, user: user, plan_type: 'basic')
      end

      it 'does not call any notification service' do
        expect(NotificationService).not_to receive(:send_subscription_notification)
        expect(NotificationService).not_to receive(:send_payment_failure_notification)

        @subscription.update(start_date: Time.current + 1.day)
      end
    end

    context 'when device_token is not present' do
      let(:user_without_token) { create(:user, device_token: nil) }

      before do
        Subscription.where(user: user_without_token).destroy_all
        @subscription = create(:subscription, user: user_without_token, status: 'active')
      end

      it 'does not send notification' do
        expect(NotificationService).not_to receive(:send_payment_failure_notification)

        @subscription.update(status: 'canceled')
      end
    end
  end

  describe '.ransackable_attributes' do
    it 'returns list of ransackable attributes' do
      expect(Subscription.ransackable_attributes).to include(
        'id', 'user_id', 'plan_type', 'status', 'stripe_subscription_id',
        'stripe_customer_id', 'start_date', 'end_date', 'created_at', 'updated_at'
      )
    end
  end

  describe '.ransackable_associations' do
    it 'returns list of ransackable associations' do
      expect(Subscription.ransackable_associations).to eq(['user'])
    end
  end
end