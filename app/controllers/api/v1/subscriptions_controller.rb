# app/controllers/api/v1/subscriptions_controller.rb
class Api::V1::SubscriptionsController < ApplicationController
  before_action :authenticate_api_v1_user!, only: [:create]
  skip_before_action :verify_authenticity_token, only: [:create, :webhook]
  skip_before_action :authenticate_api_v1_user!, only: [:webhook]

  def create
    plan_type = params[:plan_type]
    return render json: { error: 'Invalid plan' }, status: :bad_request unless %w[basic premium].include?(plan_type)
  
    stripe_price_id = case plan_type
                     when 'basic' then ENV['STRIPE_BASIC_PRICE_ID']
                     when 'premium' then ENV['STRIPE_PREMIUM_PRICE_ID']
                     end
  
    session = Stripe::Checkout::Session.create(
      customer_email: current_api_v1_user.email,
      payment_method_types: ['card'],
      line_items: [{
        price: stripe_price_id,
        quantity: 1
      }],
      mode: 'subscription',
      success_url: ENV['STRIPE_SUCCESS_URL'],
      cancel_url: ENV['STRIPE_CANCEL_URL'],
      metadata: { plan_type: plan_type }
    )
  
    render json: { session_id: session.id, checkout_url: session.url }, status: :ok
  rescue Stripe::StripeError => e
    render json: { error: e.message }, status: :bad_request
  end

  def webhook
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']

    begin
      event = Stripe::Webhook.construct_event(payload, sig_header, ENV['STRIPE_WEBHOOK_SECRET'])
    rescue Stripe::SignatureVerificationError
      return render json: { error: 'Webhook signature verification failed' }, status: :bad_request
    rescue JSON::ParserError
      return render json: { error: 'Invalid payload' }, status: :bad_request
    end

    case event.type
    when 'checkout.session.completed'
      session = event.data.object
      user = User.find_by(email: session.customer_email)
      if user
        subscription = user.subscription || user.build_subscription
        subscription.update!(
          plan_type: session.metadata.plan_type,
          status: 'active',
          stripe_subscription_id: session.subscription,
          start_date: Time.current,
          end_date: Time.current + 1.month
        )
        render json: { status: 'success' }, status: :ok
      else
        render json: { error: 'User not found' }, status: :bad_request
      end
    else
      render json: { status: 'success' }, status: :ok
    end
  end
end