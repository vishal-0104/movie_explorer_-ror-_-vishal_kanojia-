require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'associations' do
    it { should have_one(:subscription).dependent(:destroy) }
    it { should have_one_attached(:profile_picture) }
  end

  describe 'enums' do
    it { should define_enum_for(:role).with_values(user: 0, supervisor: 1) }
  end

  describe 'validations' do
    subject { build(:user) }

    it { should validate_presence_of(:first_name) }
    it { should validate_length_of(:first_name).is_at_most(100) }

    it { should validate_presence_of(:last_name) }
    it { should validate_length_of(:last_name).is_at_most(100) }

    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email).case_insensitive }
    it { should allow_value('test@example.com').for(:email) }
    it { should_not allow_value('invalid_email').for(:email) }

    it { should validate_presence_of(:mobile_number) }
    it { should allow_value('+12345678901').for(:mobile_number) }
    it { should_not allow_value('12345').for(:mobile_number).with_message('must be in E.164 format (e.g., +12345678901)') }

    it { should validate_uniqueness_of(:device_token).allow_nil }
    it { should validate_presence_of(:jti) }
    it { should validate_uniqueness_of(:jti) }

    describe 'profile_picture validations' do
      let(:user) { build(:user) }

      it 'allows valid content type (image/jpeg)' do
        valid_file = fixture_file_upload(Rails.root.join('spec', 'fixtures', 'files', 'sample.jpg'), 'image/jpeg')
        user.profile_picture.attach(valid_file)
        expect(user).to be_valid
      end

      it 'allows valid content type (image/png)' do
        valid_file = Rack::Test::UploadedFile.new(
          StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfAAAIAAH9A5M4AAAAAElFTkSuQmCC")),
          'image/png',
          original_filename: 'sample.png'
        )
        user.profile_picture.attach(valid_file)
        expect(user).to be_valid
      end

      it 'rejects invalid content types' do
        invalid_file = Rack::Test::UploadedFile.new(
          StringIO.new("%PDF-1.0\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>"),
          'application/pdf',
          original_filename: 'invalid.pdf'
        )
        user.profile_picture.attach(invalid_file)
        expect(user).not_to be_valid
        expect(user.errors[:profile_picture]).to include('has an invalid content type')
      end

      it 'rejects files larger than 5MB' do
        large_file = Rack::Test::UploadedFile.new(
          StringIO.new('a' * 6.megabytes),
          'image/jpeg',
          original_filename: 'large.jpg'
        )
        user.profile_picture.attach(large_file)
        expect(user).not_to be_valid
        expect(user.errors[:profile_picture]).to include('file size must be less than 5 MB (current size is 6 MB)')
      end

      it 'allows profile picture to be nil' do
        user.profile_picture = nil
        expect(user).to be_valid
      end
    end

    describe 'mobile_number_valid validation' do
      let(:user) { build(:user, mobile_number: '+12345678901') }
      let(:client) { instance_double(Twilio::REST::Client) }
      let(:phone_number) { instance_double('Twilio::REST::Lookups::PhoneNumberInstance') }
      let(:lookups) { double('lookups') }
      let(:v2) { double('v2') }
      let(:phone_numbers) { double('phone_numbers') }

      before do
        allow(ENV).to receive(:[]).with('TWILIO_ACCOUNT_SID').and_return('test')
        allow(ENV).to receive(:[]).with('TWILIO_AUTH_TOKEN').and_return('test_token')
        allow(Twilio::REST::Client).to receive(:new).with('test', 'test_token').and_return(client)
        allow(client).to receive(:lookups).and_return(lookups)
        allow(lookups).to receive(:v2).and_return(v2)
        allow(v2).to receive(:phone_numbers).with('+12345678901').and_return(phone_numbers)
        allow(phone_numbers).to receive(:fetch).with(fields: 'validation').and_return(phone_number)
      end

      context 'when not in test environment' do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
        end

        it 'validates mobile number successfully with Twilio' do
          allow(phone_number).to receive(:valid).and_return(true)
          expect(user).to be_valid
        end

        it 'adds error when mobile number is invalid according to Twilio' do
          allow(phone_number).to receive(:valid).and_return(false)
          user.valid?
          expect(user.errors[:mobile_number]).to include('is not a valid phone number')
        end
      end

      context 'when in test environment' do
        it 'skips Twilio validation' do
          expect(Rails.env.test?).to be true
          expect(client).not_to receive(:lookups)
          expect(user).to be_valid
        end
      end
    end
  end

  describe 'callbacks' do
    it 'downcases the email before save' do
      user = create(:user, email: 'Test@Example.com')
      expect(user.email).to eq('test@example.com')
    end

    it 'creates a default subscription after creation' do
      user = create(:user)
      expect(user.subscription).to be_present
      expect(user.subscription.plan_type).to eq('free')
      expect(user.subscription.status).to eq('active')
      expect(user.subscription.start_date).to be_within(1.second).of(Time.current)
    end

    it 'does not create a new subscription if one already exists' do
      user = create(:user)
      original_subscription = user.subscription
      user.save
      expect(user.subscription).to eq(original_subscription)
    end
  end

  describe 'scopes' do
    let!(:active_user) do
      create(:user, mobile_number: '+12345678901').tap do |user|
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
      create(:user, mobile_number: '+12345678902').tap do |user|
        user.subscription.update!(
          plan_type: 'premium',
          status: 'cancelled',
          end_date: 1.day.ago,
          stripe_customer_id: 'cus_456',
          stripe_subscription_id: 'sub_456'
        )
      end
    end

    let!(:no_end_date_user) do
      create(:user, mobile_number: '+12345678903').tap do |user|
        user.subscription.update!(
          plan_type: 'free',
          status: 'active',
          end_date: nil,
          stripe_customer_id: nil,
          stripe_subscription_id: nil
        )
      end
    end

    it '.with_active_subscription returns only users with active subscriptions' do
      result = User.with_active_subscription
      expect(result).to include(active_user)
      expect(result).to include(no_end_date_user)
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

      it 'returns false for user role' do
        user.update!(role: :user)
        expect(user.supervisor?).to be false
      end
    end

    describe '#common_user?' do
      it 'returns true for user role' do
        user.update!(role: :user)
        expect(user.common_user?).to be true
      end

      it 'returns false for supervisor role' do
        user.update!(role: :supervisor)
        expect(user.common_user?).to be false
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

      it 'returns true if subscription is active and basic' do
        user.subscription.update!(
          plan_type: 'basic',
          status: 'active',
          end_date: 1.month.from_now,
          stripe_customer_id: "cus_#{SecureRandom.hex(6)}",
          stripe_subscription_id: "sub_#{SecureRandom.hex(6)}"
        )
        expect(user.premium?).to be true
      end

      it 'returns false for cancelled subscription' do
        user.subscription.update!(
          plan_type: 'premium',
          status: 'cancelled',
          end_date: 1.month.from_now,
          stripe_customer_id: 'cus_def',
          stripe_subscription_id: 'sub_def'
        )
        expect(user.premium?).to be false
      end

      it 'returns false for free plan' do
        user.subscription.update!(plan_type: 'free', status: 'active', stripe_subscription_id: nil, stripe_customer_id: nil, end_date: nil)
        expect(user.premium?).to be false
      end

      it 'returns false if no subscription' do
        user = create(:user, :without_subscription)
        expect(user.premium?).to be false
      end
    end

    describe '#can_access_premium_movies?' do
      it 'returns true for active premium subscription' do
        user.subscription.update!(
          plan_type: 'premium',
          status: 'active',
          end_date: 1.month.from_now,
          stripe_customer_id: 'cus_abc',
          stripe_subscription_id: 'sub_abc'
        )
        expect(user.can_access_premium_movies?).to be true
      end

      it 'returns true for cancelled premium subscription with future end_date' do
        user.subscription.update!(
          plan_type: 'premium',
          status: 'cancelled',
          end_date: 1.month.from_now,
          stripe_customer_id: 'cus_abc',
          stripe_subscription_id: 'sub_abc'
        )
        expect(user.can_access_premium_movies?).to be true
      end

      it 'returns false for cancelled premium subscription with past end_date' do
        user.subscription.update!(
          plan_type: 'premium',
          status: 'cancelled',
          end_date: 1.day.ago,
          stripe_customer_id: 'cus_abc',
          stripe_subscription_id: 'sub_abc'
        )
        expect(user.can_access_premium_movies?).to be false
      end

      it 'returns true for active basic subscription' do
        user.subscription.update!(
          plan_type: 'basic',
          status: 'active',
          end_date: 1.month.from_now,
          stripe_customer_id: "cus_#{SecureRandom.hex(6)}",
          stripe_subscription_id: "sub_#{SecureRandom.hex(6)}"
        )
        expect(user.can_access_premium_movies?).to be true
      end

      it 'returns false for free plan' do
        user.subscription.update!(plan_type: 'free', status: 'active', stripe_subscription_id: nil, stripe_customer_id: nil, end_date: nil)
        expect(user.can_access_premium_movies?).to be false
      end

      it 'returns false if no subscription' do
        user = create(:user, :without_subscription)
        expect(user.can_access_premium_movies?).to be false
      end
    end

    describe '#jwt_payload' do
      it 'includes expected keys in the payload' do
        payload = user.jwt_payload
        expect(payload.keys).to contain_exactly(:role, :user_id, :scp)
        expect(payload[:role]).to eq(user.role)
        expect(payload[:user_id]).to eq(user.id)
        expect(payload[:scp]).to eq('api_v1_user')
      end
    end
  end

  describe '.ransackable_attributes' do
    it 'includes searchable attributes' do
      expect(User.ransackable_attributes).to match_array(
        %w[id email role created_at updated_at first_name last_name mobile_number]
      )
    end
  end

  describe '.ransackable_associations' do
    it 'includes searchable associations' do
      expect(User.ransackable_associations).to match_array(%w[subscription])
    end
  end
end