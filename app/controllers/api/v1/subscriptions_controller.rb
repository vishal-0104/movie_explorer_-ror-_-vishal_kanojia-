# app/controllers/api/v1/subscriptions_controller.rb
class Api::V1::SubscriptionsController < ApplicationController
  before_action :authenticate_api_v1_user!, only: [:create]
  skip_before_action :verify_authenticity_token, only: [:create, :webhook]
  skip_before_action :authenticate_api_v1_user!, only: [:webhook]

  def create
    Stripe.api_key = ENV['STRIPE_SECRET_KEY']
    
    unless valid_plan_type?
      return render json: { error: 'Invalid plan type' }, status: :bad_request
    end

    begin
      session = Stripe::Checkout::Session.create(
        customer_email: current_api_v1_user.email,
        payment_method_types: ['card'],
        line_items: [{
          price: stripe_price_id,
          quantity: 1
        }],
        mode: 'subscription',
        success_url: success_url,
        cancel_url: ENV['STRIPE_CANCEL_URL'],
        metadata: { 
          plan_type: params[:plan_type],
          user_id: current_api_v1_user.id
        },
        subscription_data: {
          metadata: {
            user_id: current_api_v1_user.id
          }
        }
      )

      render json: { session_id: session.id, checkout_url: session.url }, status: :ok
    rescue Stripe::StripeError => e
      Rails.logger.error("Stripe error: #{e.message}")
      render json: { error: 'Payment processing failed. Please try again.' }, status: :bad_request
    rescue StandardError => e
      Rails.logger.error("Unexpected error: #{e.message}")
      render json: { error: 'An unexpected error occurred.' }, status: :internal_server_error
    end
  end

  def webhook
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']

    begin
      event = Stripe::Webhook.construct_event(
        payload,
        sig_header,
        ENV['STRIPE_WEBHOOK_SECRET']
      )
    rescue Stripe::SignatureVerificationError => e
      Rails.logger.error("Webhook signature verification failed: #{e.message}")
      return render json: { error: 'Invalid webhook signature' }, status: :bad_request
    rescue JSON::ParserError => e
      Rails.logger.error("Invalid payload: #{e.message}")
      return render json: { error: 'Invalid payload' }, status: :bad_request
    end

    case event.type
    when 'checkout.session.completed'
      handle_checkout_session_completed(event.data.object)
    when 'customer.subscription.updated', 'customer.subscription.deleted'
      handle_subscription_change(event.data.object)
    when 'invoice.payment_failed'
      handle_payment_failure(event.data.object)
    else
      Rails.logger.info("Unhandled event type: #{event.type}")
      render json: { status: 'success' }, status: :ok
    end
  end

  private

  def valid_plan_type?
    %w[basic premium].include?(params[:plan_type])
  end

  def stripe_price_id
    case params[:plan_type]
    when 'basic' then ENV['STRIPE_BASIC_PRICE_ID']
    when 'premium' then ENV['STRIPE_PREMIUM_PRICE_ID']
    end
  end

  def success_url
    ENV['STRIPE_SUCCESS_URL'].gsub('session_id=', "session_id=#{params[:session_id]}")
  end

  def handle_checkout_session_completed(session)
    user = User.find_by(id: session.metadata.user_id) || User.find_by(email: session.customer_email)
    
    unless user
      Rails.logger.error("User not found for session: #{session.id}")
      return render json: { error: 'User not found' }, status: :bad_request
    end

    begin
      subscription = user.subscription || user.build_subscription
      subscription.update!(
        plan_type: session.metadata.plan_type,
        status: 'active',
        stripe_subscription_id: session.subscription,
        stripe_customer_id: session.customer,
        start_date: Time.current,
        end_date: calculate_end_date
      )

      # Send FCM notification using NotificationService
      NotificationService.send_subscription_notification(user, session.metadata.plan_type)

      render json: { status: 'success' }, status: :ok
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("Subscription update failed: #{e.message}")
      render json: { error: 'Subscription creation failed' }, status: :bad_request
    end
  end

  def handle_subscription_change(subscription)
    user = User.find_by(id: subscription.metadata.user_id)
    
    return unless user && user.subscription
    
    status = subscription.status == 'active' ? 'active' : 'inactive'
    
    user.subscription.update(
      status: status,
      end_date: subscription.cancel_at_period_end ? 
                Time.at(subscription.current_period_end) : 
                calculate_end_date
    )
    
    render json: { status: 'success' }, status: :ok
  end

  def handle_payment_failure(invoice)
    user = User.find_by(stripe_customer_id: invoice.customer)
    
    if user && user.subscription
      user.subscription.update(status: 'past_due')
      # Send FCM notification using NotificationService
      NotificationService.send_payment_failure_notification(user)
    end
    
    render json: { status: 'success' }, status: :ok
  end

  def calculate_end_date
    Time.current + 1.month
  end
end