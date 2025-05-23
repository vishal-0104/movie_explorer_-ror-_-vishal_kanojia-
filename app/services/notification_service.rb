require 'httparty'
require 'googleauth'

class NotificationService
  ACCESS_TOKEN_CACHE_KEY = 'fcm_access_token'.freeze
  ACCESS_TOKEN_EXPIRY = 55.minutes
  @mutex = Mutex.new

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
    Rails.logger.error("Failed to fetch FCM access token: #{e.message}")
    raise
  end

  def self.send_fcm_notification(tokens, title, body, data = {})
    return if tokens.empty?

    valid_tokens = tokens.uniq.select { |t| t&.match?(/\A[a-zA-Z0-9:_\-\.]{100,200}\z/) }
    invalid_tokens = tokens - valid_tokens
    invalid_tokens.each do |token|
      Rails.logger.warn("Skipping invalid FCM token: #{token}")
      User.where(device_token: token).update_all(device_token: nil) if token.match?(/\AeyJ/)
    end

    return if valid_tokens.empty?

    headers = {
      'Authorization': "Bearer #{get_access_token}",
      'Content-Type': 'application/json'
    }

    responses = []
    valid_tokens.each do |token|
      payload = {
        message: {
          token: token,
          notification: {
            title: title,
            body: body
          },
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
        Rails.logger.error("FCM notification failed for token #{token}: #{response.body}")
      end

      responses << response
    end

    handle_response_errors(responses, valid_tokens)
    responses
  rescue StandardError => e
    Rails.logger.error("FCM notification error: #{e.message}")
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

    Rails.logger.info("Sending subscription notification for user #{user.id}, plan: #{plan_type}")
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
      Rails.logger.info("Subscription notification sent successfully for user #{user.id}")
    else
      Rails.logger.error("Failed to send subscription notification for user #{user.id}")
    end
  end

  def self.send_payment_failure_notification(user)
    return unless user.device_token

    Rails.logger.info("Sending payment failure notification for user #{user.id}")
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
      Rails.logger.info("Payment failure notification sent successfully for user #{user.id}")
    else
      Rails.logger.error("Failed to send payment failure notification for user #{user.id}")
    end
  end

  def self.send_cancellation_notification(user)
    return unless user.device_token

    Rails.logger.info("Sending cancellation notification for user #{user.id}")
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
      Rails.logger.info("Cancellation notification sent successfully for user #{user.id}")
    else
      Rails.logger.error("Failed to send cancellation notification for user #{user.id}")
    end
  end

  private

  def self.send_movie_notification(movie, title_prefix, body_action, event_type)
    @mutex.synchronize do
      movie_data = {
        id: movie.id,
        title: movie.title,
        premium: movie.premium
      }

      users = movie_data[:premium] ? User.with_active_subscription : User.all
      eligible_users = users.where.not(device_token: nil)
                           .where("users.updated_at < ?", 1.minute.ago)
                           .select(:id, :device_token)
      device_tokens = eligible_users.pluck(:device_token).uniq

      return if device_tokens.empty?

      base_url = ENV['APP_BASE_URL']
      movie_url = "#{base_url}/movies/#{movie_data[:id]}"

      Rails.logger.info("Sending #{title_prefix} notification for movie #{movie_data[:id]} to #{device_tokens.size} users")

      response = send_fcm_notification(
        device_tokens,
        title_prefix,
        "#{movie_data[:title]} #{body_action}#{movie_data[:premium] ? ' for premium users' : ''}!",
        {
          movie_id: movie_data[:id].to_s,
          title: movie_data[:title],
          premium: movie_data[:premium].to_s,
          action: event_type,
          notification_type: "movie",
          url: movie_url
        }
      )

      if response&.any?(&:success?)
        Rails.logger.info("Movie notification (#{title_prefix}) sent to #{device_tokens.size} tokens")
        eligible_users.update_all(updated_at: Time.current)
      else
        Rails.logger.error("Failed to send movie notification (#{title_prefix}) to tokens")
      end
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

      if token.match?(/\AeyJ/)
        Rails.logger.warn("Invalid device_token detected: JWT used instead of FCM token (#{token})")
        User.where(device_token: token).update_all(device_token: nil)
      elsif fcm_error_code == 'UNREGISTERED' || error_message&.include?('NotRegistered') || error_message&.include?('InvalidRegistration')
        User.where(device_token: token).update_all(device_token: nil)
        Rails.logger.info("Removed invalid FCM token: #{token}")
      end
    end
  end
end