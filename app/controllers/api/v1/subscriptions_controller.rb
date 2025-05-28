class Api::V1::SubscriptionsController < ApplicationController
  before_action :authenticate_api_v1_user!, only: [:create, :status, :confirm, :cancel]
  skip_before_action :verify_authenticity_token, only: [:create, :webhook, :confirm, :cancel]
  skip_before_action :authenticate_api_v1_user!, only: [:webhook]

  def create
    plan_id = params[:subscription]&.[](:plan_id) || params[:plan_id]
    unless Subscription.plan_types.key?(plan_id)
      return render json: { error: "Invalid plan type", errors: ["Plan '#{plan_id}' is not valid"] }, status: :bad_request
    end

    @current_user.subscription&.destroy

    duration = plan_id == "basic" ? 7.days : 1.month
    subscription = @current_user.build_subscription(
      plan_type: plan_id,
      status: plan_id == "free" ? "active" : "pending",
      start_date: Time.current,
      end_date: Time.current + duration
    )

    if plan_id == "free"
      subscription.save!
      NotificationService.send_subscription_notification(@current_user, plan_id) if @current_user.device_token || @current_user.mobile_number
      return render json: { plan: subscription.plan_type, status: subscription.status, current_period_end: subscription.end_date }, status: :created
    end

    begin
      customer = Stripe::Customer.create(email: @current_user.email)
      subscription.stripe_customer_id = customer.id
      subscription.save!

      payment_intent = Stripe::PaymentIntent.create(
        customer: customer.id,
        amount: calculate_amount(plan_id),
        currency: "usd",
        payment_method_types: ["card"],
        metadata: { user_id: @current_user.id, plan_id: plan_id }
      )

      render json: {
        client_secret: payment_intent.client_secret,
        payment_intent_id: payment_intent.id,
        subscription_id: subscription.id
      }, status: :ok
    rescue Stripe::StripeError => e
      Rails.logger.error "Stripe error: #{e.message}"
      render json: { error: "Payment intent creation failed", errors: [e.message] }, status: :unprocessable_entity
    end
  end

  def cancel
  subscription = @current_user.subscription
  unless subscription
    create_free_subscription
    subscription = @current_user.subscription
    return render json: {
      message: "No subscription found. Set to free plan.",
      plan: subscription.plan_type,
      status: subscription.status,
      current_period_end: subscription.end_date
    }, status: :ok
  end

  unless subscription.active? || subscription.past_due?
    return render json: {
      error: "No active or past due subscription to cancel",
      errors: ["Subscription is #{subscription.status}"]
    }, status: :bad_request
  end

  begin
    if subscription.stripe_subscription_id && subscription.plan_type != "free"
      Rails.logger.info "Cancelling subscription with PaymentIntent ID: #{subscription.stripe_subscription_id}"
    end

    subscription.update!(status: "cancelled")
    if @current_user.device_token || @current_user.mobile_number
      NotificationService.send_cancellation_notification(@current_user)
    else
      Rails.logger.info("No device token or mobile number for user #{@current_user.id}; skipping cancellation notification")
    end

    render json: {
      message: "Subscription cancelled successfully. You will revert to the free plan after #{subscription.end_date}.",
      plan: subscription.plan_type,
      status: subscription.status,
      current_period_end: subscription.end_date
    }, status: :ok
  rescue Stripe::StripeError => e
    Rails.logger.error "Stripe error during cancellation: #{e.message}"
    render json: { error: "Cancellation failed", errors: [e.message] }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error "Error during cancellation: #{e.message}"
    render json: { error: "Cancellation failed", errors: [e.message] }, status: :unprocessable_entity
  end
  end

  def confirm
    subscription = @current_user.subscription
    Rails.logger.info "Subscription: #{subscription&.inspect}"
    unless subscription&.pending?
      Rails.logger.error "No pending subscription found for user #{@current_user.id}"
      return render json: { error: "No pending subscription found", errors: ["Subscription is not pending"] }, status: :bad_request
    end

    payment_intent_id = params[:subscription]&.[](:payment_intent_id) || params[:payment_intent_id]
    Rails.logger.info "Payment intent ID: #{payment_intent_id}"
    begin
      payment_intent = Stripe::PaymentIntent.retrieve(payment_intent_id)
      Rails.logger.info "Payment intent status: #{payment_intent.status}, customer: #{payment_intent.customer}"
      unless payment_intent.status == "succeeded"
        Rails.logger.error "Payment intent not succeeded: #{payment_intent.status}"
        return render json: { error: "Payment not completed", errors: ["Payment intent has not succeeded"] }, status: :bad_request
      end

      duration = subscription.plan_type == "basic" ? 7.days : 1.month
      subscription.update!(
        status: "active",
        stripe_subscription_id: payment_intent.id,
        end_date: Time.current + duration
      )
      NotificationService.send_subscription_notification(@current_user, subscription.plan_type) if @current_user.device_token || @current_user.mobile_number

      render json: {
        plan: subscription.plan_type,
        status: subscription.status,
        current_period_end: subscription.end_date
      }, status: :ok
    rescue Stripe::StripeError => e
      Rails.logger.error "Stripe error: #{e.message}"
      render json: { error: "Payment confirmation failed", errors: [e.message] }, status: :unprocessable_entity
    end
  end

  def status
    subscription = @current_user.subscription
    unless subscription
      create_free_subscription
      subscription = @current_user.subscription
      return render json: {
        plan: subscription.plan_type,
        status: subscription.status,
        current_period_end: subscription.end_date
      }, status: :ok
    end

    if subscription.status == "cancelled" && subscription.end_date && Time.current > subscription.end_date
      subscription.destroy
      create_free_subscription
      subscription = @current_user.subscription
    end

    render json: {
      plan: subscription.plan_type,
      status: subscription.status,
      current_period_end: subscription.end_date
    }, status: :ok
  end

  def webhook
    payload = request.body.read
    sig_header = request.env["HTTP_STRIPE_SIGNATURE"]
    endpoint_secret = ENV["STRIPE_WEBHOOK_SECRET"]

    begin
      event = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
    rescue JSON::ParserError, Stripe::SignatureVerificationError => e
      Rails.logger.error("Webhook error: #{e.message}")
      return render json: { error: "Invalid webhook", errors: [e.message] }, status: :bad_request
    end

    cache_key = "stripe_webhook_#{event.id}"
    if Rails.cache.exist?(cache_key)
      Rails.logger.info("Webhook event #{event.id} already processed")
      return render json: { status: "success" }, status: :ok
    end

    case event.type
    when "payment_intent.succeeded"
      handle_payment_intent_succeeded(event.data.object)
    when "payment_intent.payment_failed"
      handle_payment_intent_failed(event.data.object)
    when "invoice.payment_failed"
      handle_payment_failure(event.data.object)
    else
      Rails.logger.info("Unhandled event type: #{event.type}")
    end

    Rails.cache.write(cache_key, true, expires_in: 24.hours)
    render json: { status: "success" }, status: :ok
  end

  private

  def get_or_create_stripe_customer
    if @current_user.subscription&.stripe_customer_id
      return @current_user.subscription.stripe_customer_id
    end
    customer = Stripe::Customer.create(email: @current_user.email)
    customer.id
  end

  def calculate_amount(plan_id)
    case plan_id
    when "basic" then 999
    when "premium" then 1499
    else raise "Invalid plan"
    end
  end

  def handle_payment_intent_succeeded(payment_intent)
    user = User.find_by(id: payment_intent.metadata["user_id"])
    return unless user&.subscription

    subscription = user.subscription
    return unless subscription.status == "pending"

    duration = subscription.plan_type == "basic" ? 7.days : 1.month
    subscription.update!(
      status: "active",
      stripe_subscription_id: payment_intent.id,
      end_date: Time.current + duration
    )
    NotificationService.send_subscription_notification(user, subscription.plan_type) if user.device_token || user.mobile_number
  rescue => e
    Rails.logger.error("Error in handle_payment_intent_succeeded: #{e.message}")
  end

  def handle_payment_intent_failed(payment_intent)
    user = User.find_by(id: payment_intent.metadata["user_id"])
    return unless user&.subscription

    subscription = user.subscription
    return if subscription.status == "cancelled"

    subscription.update!(status: "past_due")
    NotificationService.send_payment_failure_notification(user) if user.device_token || user.mobile_number
  rescue => e
    Rails.logger.error("Error in handle_payment_intent_failed: #{e.message}")
  end

  def handle_payment_failure(invoice)
    customer_id = invoice.customer
    user = User.find_by(stripe_customer_id: customer_id)
    return unless user&.subscription

    subscription = user.subscription
    return if subscription.status == "cancelled"

    subscription.update!(status: "past_due")
    NotificationService.send_payment_failure_notification(user) if user.device_token || user.mobile_number
  rescue => e
    Rails.logger.error("Error in handle_payment_failure: #{e.message}")
  end

  def create_free_subscription
    @current_user.subscription&.destroy
    @current_user.build_subscription(
      plan_type: "free",
      status: "active",
      start_date: Time.current,
      end_date: nil
    ).save!
    NotificationService.send_cancellation_notification(@current_user) if @current_user.device_token || @current_user.mobile_number
  end
end