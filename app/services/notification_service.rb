require 'httparty'
require 'googleauth'

class NotificationService
  ACCESS_TOKEN_CACHE_KEY = 'fcm_access_token'.freeze
  ACCESS_TOKEN_EXPIRY = 55.minutes

  def self.get_access_token
    cached_token = Rails.cache.read(ACCESS_TOKEN_CACHE_KEY)
    return cached_token if cached_token

    credentials = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(ENV['FCM_SERVICE_ACCOUNT_JSON'] || File.read(Rails.root.join('config/credentials/fcm-service-account.json'))),
      scope: 'https://www.googleapis.com/auth/firebase.messaging'
    )
    token = credentials.fetch_access_token!['access_token']
    Rails.cache.write(ACCESS_TOKEN_CACHE_KEY, token, expires_in: ACCESS_TOKEN_EXPIRY)
    token
  rescue StandardError => e
    Rails.logger.error("Failed to fetch FCM access token: #{e.message}, Backtrace: #{e.backtrace.join("\n")}")
    nil
  end

  def self.send_fcm_notification(tokens, title, body, data = {})
    return if tokens.blank?

    # Relaxed token validation to avoid false negatives
    valid_tokens = tokens.uniq.select { |t| t.present? && t.length > 50 }
    invalid_tokens = tokens - valid_tokens
    invalid_tokens.each do |token|
      Rails.logger.warn("Invalid FCM token: #{token} (length: #{token&.length || 0})")
      User.where(device_token: token).update_all(device_token: nil)
    end

    if valid_tokens.empty?
      Rails.logger.info("No valid tokens to send FCM notification. Provided tokens: #{tokens.inspect}")
      return
    end

    access_token = get_access_token
    unless access_token
      Rails.logger.error("No FCM access token available")
      return
    end

    headers = {
      'Authorization': "Bearer #{access_token}",
      'Content-Type': 'application/json'
    }

    responses = []
    valid_tokens.each do |token|
      payload = {
        message: {
          token: token,
          notification: { title: title, body: body },
          data: data.transform_keys(&:to_s)
        }
      }.to_json

      response = HTTParty.post(
        "https://fcm.googleapis.com/v1/projects/#{ENV['FCM_PROJECT_ID']}/messages:send",
        headers: headers,
        body: payload
      )

      if response.success?
        Rails.logger.info("FCM notification sent to token: #{token}, title: #{title}")
      else
        Rails.logger.error("FCM notification failed for token: #{token}, status: #{response.code}, body: #{response.body}")
      end
      responses << response
    end

    handle_response_errors(responses, valid_tokens)
    responses
  rescue StandardError => e
    Rails.logger.error("FCM notification error: #{e.message}, Backtrace: #{e.backtrace.join("\n")}")
    nil
  end

  def self.send_new_movie_notification(movie)
    send_movie_notification(movie, "New Movie Added", "is now available", "movie_added")
  end

  def self.send_updated_movie_notification(movie)
    return if movie.destroyed?
    send_movie_notification(movie, "Movie Updated", "has been updated", "movie_updated")
  end

  def self.send_deleted_movie_notification(movie)
    send_movie_notification(movie, "Movie Removed", "is no longer available", "movie_removed")
  end

  def self.send_subscription_notification(user, plan_type)
    return unless user.device_token

    cache_key = "notification:subscription_activated:#{user.id}:#{plan_type}:#{Time.current.to_i / 3600}"
    return if Rails.cache.exist?(cache_key)

    response = send_fcm_notification(
      [user.device_token],
      "Subscription Activated!",
      "Your #{plan_type.capitalize} subscription has been successfully activated.",
      {
        plan_type: plan_type,
        subscription_id: user.subscription&.stripe_subscription_id || '',
        action: "subscription_activated",
        notification_type: "subscription"
      }
    )

    if response&.any?(&:success?)
      Rails.cache.write(cache_key, true, expires_in: 1.hour)
      Rails.logger.info("Subscription notification sent for user #{user.id}")
    else
      Rails.logger.error("Failed to send subscription notification for user #{user.id}")
    end
  end

  def self.send_payment_failure_notification(user)
    return unless user.device_token

    cache_key = "notification:payment_failure:#{user.id}:#{Time.current.to_i / 3600}"
    return if Rails.cache.exist?(cache_key)

    response = send_fcm_notification(
      [user.device_token],
      "Payment Failed",
      "There was an issue with your subscription payment. Please update your payment method.",
      {
        type: "payment_failure",
        action: "payment_failed",
        notification_type: "payment"
      }
    )

    if response&.any?(&:success?)
      Rails.cache.write(cache_key, true, expires_in: 1.hour)
      Rails.logger.info("Payment failure notification sent for user #{user.id}")
    else
      Rails.logger.error("Failed to send payment failure notification for user #{user.id}")
    end
  end

  def self.send_cancellation_notification(user)
    return unless user.device_token

    cache_key = "notification:subscription_cancelled:#{user.id}:#{Time.current.to_i / 3600}"
    return if Rails.cache.exist?(cache_key)

    response = send_fcm_notification(
      [user.device_token],
      "Subscription Cancelled",
      "Your subscription has been cancelled. You are now on the free plan.",
      {
        type: "subscription_cancellation",
        action: "subscription_cancelled",
        notification_type: "subscription"
      }
    )

    if response&.any?(&:success?)
      Rails.cache.write(cache_key, true, expires_in: 1.hour)
      Rails.logger.info("Cancellation notification sent for user #{user.id}")
    else
      Rails.logger.error("Failed to send cancellation notification for user #{user.id}")
    end
  end

  private

  def self.send_movie_notification(movie, title_prefix, body_action, event_type)
    cache_key = "notification:#{event_type}:#{movie.id}"
    return if Rails.cache.exist?(cache_key)

    # Select all users regardless of premium status
    users = User.all
    device_tokens = users.where.not(device_token: nil).pluck(:device_token).uniq

    # Log detailed information if no eligible users are found
    if device_tokens.empty?
      Rails.logger.info(
        "No eligible users for #{title_prefix} notification for movie #{movie.id}. " +
        "Premium: #{movie.premium}, " +
        "Total users: #{User.count}, " +
        "Users with device tokens: #{User.where.not(device_token: nil).count}, " +
        "Device tokens: #{device_tokens.inspect}"
      )
      return
    end

    base_url = ENV['APP_BASE_URL'] || 'http://localhost:3000'
    movie_url = "#{base_url}/movies/#{movie.id}"

    response = send_fcm_notification(
      device_tokens,
      title_prefix,
      "#{movie.title} #{body_action}!",
      {
        movie_id: movie.id.to_s,
        title: movie.title,
        premium: movie.premium.to_s,
        action: event_type,
        notification_type: "movie",
        url: movie_url
      }
    )

    if response&.any?(&:success?)
      Rails.cache.write(cache_key, true, expires_in: 1.hour)
      Rails.logger.info("Sent #{title_prefix} notification for movie #{movie.id} to #{device_tokens.size} users")
    else
      Rails.logger.error("Failed to send #{title_prefix} notification for movie #{movie.id}")
    end
  end

  def self.handle_response_errors(responses, tokens)
    responses.each_with_index do |response, index|
      next unless response.parsed_response&.dig('error')

      error_code = response.parsed_response.dig('error', 'code')
      error_message = response.parsed_response.dig('error', 'message')
      fcm_error_code = response.parsed_response.dig('error', 'details')&.find { |d| d['@type'] == 'type.googleapis.com/google.firebase.fcm.v1.FcmError' }&.dig('errorCode')
      token = tokens[index]

      Rails.logger.warn("FCM error for token #{token}: #{error_code} - #{error_message}#{fcm_error_code ? " (FCM errorCode: #{fcm_error_code})" : ''}")

      if fcm_error_code == 'UNREGISTERED' || error_message&.include?('NotRegistered') || error_message&.include?('InvalidRegistration')
        User.where(device_token: token).update_all(device_token: nil)
        Rails.logger.info("Removed invalid FCM token: #{token}")
      end
    end
  end
end