# app/controllers/api/v1/subscriptions_controller.rb
class Api::V1::SubscriptionsController < ApplicationController
  before_action :authenticate_api_v1_user!, only: [:create, :status, :confirm]
  skip_before_action :verify_authenticity_token, only: [:create, :webhook, :confirm]
  skip_before_action :authenticate_api_v1_user!, only: [:webhook]

  # POST /api/v1/subscriptions
  def create
    plan_id = params[:subscription]&.[](:plan_id) || params[:plan_id]
    unless Subscription.plan_types.key?(plan_id)
      return render json: { error: 'Invalid plan type', errors: ["Plan '#{plan_id}' is not valid"] }, status: :bad_request
    end

    # Destroy existing subscription
    current_api_v1_user.subscription&.destroy

    subscription = current_api_v1_user.build_subscription(
      plan_type: plan_id,
      status: plan_id == 'free' ? 'active' : 'pending',
      start_date: Time.current,
      end_date: Time.current + 1.month
    )

    if plan_id == 'free'
      subscription.save!
      return render json: { plan: subscription.plan_type, status: subscription.status, current_period_end: subscription.end_date }, status: :created
    end

    begin
      customer = Stripe::Customer.create(email: current_api_v1_user.email)
      subscription.stripe_customer_id = customer.id
      subscription.save!

      payment_intent = Stripe::PaymentIntent.create(
        customer: customer.id,
        amount: plan_id == 'basic' ? 50000 : 100000, # $5 or $10 in cents
        currency: 'usd',
        payment_method_types: ['card'],
        metadata: { user_id: current_api_v1_user.id, plan_id: plan_id }
      )

      render json: {
        client_secret: payment_intent.client_secret,
        payment_intent_id: payment_intent.id,
        subscription_id: subscription.id
      }, status: :ok
    rescue Stripe::StripeError => e
      Rails.logger.error "Stripe error: #{e.message}"
      render json: { error: 'Payment intent creation failed', errors: [e.message] }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/subscriptions/confirm
  def confirm
    subscription = current_api_v1_user.subscription
    Rails.logger.info "Subscription: #{subscription&.inspect}"
    unless subscription&.pending?
      Rails.logger.error "No pending subscription found for user #{current_api_v1_user.id}"
      return render json: { error: 'No pending subscription found', errors: ['Subscription is not pending'] }, status: :bad_request
    end
  
    payment_intent_id = params[:subscription]&.[](:payment_intent_id) || params[:payment_intent_id]
    Rails.logger.info "Payment intent ID: #{payment_intent_id}"
    begin
      payment_intent = Stripe::PaymentIntent.retrieve(payment_intent_id)
      Rails.logger.info "Payment intent status: #{payment_intent.status}, customer: #{payment_intent.customer}"
      unless payment_intent.status == 'succeeded'
        Rails.logger.error "Payment intent not succeeded: #{payment_intent.status}"
        return render json: { error: 'Payment not completed', errors: ['Payment intent has not succeeded'] }, status: :bad_request
      end
  
      subscription.update!(
        status: 'active',
        stripe_subscription_id: payment_intent.id,
        end_date: Time.current + 1.month
      )
      NotificationService.send_subscription_notification(current_api_v1_user, subscription) if current_api_v1_user.device_token
  
      render json: {
        plan: subscription.plan_type,
        status: subscription.status,
        current_period_end: subscription.end_date
      }, status: :ok
    rescue Stripe::StripeError => e
      Rails.logger.error "Stripe error: #{e.message}"
      render json: { error: 'Payment confirmation failed', errors: [e.message] }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/subscriptions/status
  def status
    subscription = current_api_v1_user.subscription
    unless subscription
      return render json: { error: 'No active subscription found', errors: ['User has no subscription'] }, status: :not_found
    end

    render json: {
      plan: subscription.plan_type,
      status: subscription.status,
      current_period_end: subscription.end_date
    }, status: :ok
  end

  # POST /api/v1/webhooks/stripe
  def webhook
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    endpoint_secret = ENV['STRIPE_WEBHOOK_SECRET']

    begin
      event = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
    rescue JSON::ParserError, Stripe::SignatureVerificationError => e
      Rails.logger.error("Webhook error: #{e.message}")
      return render json: { error: 'Invalid webhook', errors: [e.message] }, status: :bad_request
    end

    case event.type
    when 'payment_intent.succeeded'
      handle_payment_intent_succeeded(event.data.object)
    when 'payment_intent.payment_failed'
      handle_payment_intent_failed(event.data.object)
    when 'invoice.payment_failed'
      handle_payment_failure(event.data.object)
    else
      Rails.logger.info("Unhandled event type: #{event.type}")
    end

    render json: { status: 'success' }, status: :ok
  end

  private

  def get_or_create_stripe_customer
    if current_api_v1_user.subscription&.stripe_customer_id
      return current_api_v1_user.subscription.stripe_customer_id
    end
    customer = Stripe::Customer.create(email: current_api_v1_user.email)
    customer.id
  end

  def calculate_amount(plan_id)
    # Define your pricing logic here
    case plan_id
    when 'basic' then 999 # $9.99
    when 'premium' then 1999 # $19.99
    else raise 'Invalid plan'
    end
  end

  def handle_payment_intent_succeeded(payment_intent)
    user = User.find_by(id: payment_intent.metadata['user_id'])
    return unless user&.subscription

    subscription = user.subscription
    return unless subscription.status == 'pending'

    subscription.update!(
      status: 'active',
      stripe_subscription_id: payment_intent.id
    )
    NotificationService.send_subscription_notification(user, subscription.plan_type)
  rescue => e
    Rails.logger.error("Error in handle_payment_intent_succeeded: #{e.message}")
  end

  def handle_payment_intent_failed(payment_intent)
    user = User.find_by(id: payment_intent.metadata['user_id'])
    return unless user&.subscription

    subscription = user.subscription
    subscription.update!(status: 'past_due')
    NotificationService.send_payment_failure_notification(user)
  rescue => e
    Rails.logger.error("Error in handle_payment_intent_failed: #{e.message}")
  end

  def handle_payment_failure(invoice)
    customer_id = invoice.customer
    user = User.find_by(stripe_customer_id: customer_id)
    return unless user&.subscription

    user.subscription.update!(status: 'past_due')
    NotificationService.send_payment_failure_notification(user)
  rescue => e
    Rails.logger.error("Error in handle_payment_failure: #{e.message}")
  end
end