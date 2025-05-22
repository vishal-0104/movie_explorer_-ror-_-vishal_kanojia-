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
    Rails.logger.error("Failed to fetch FCM access token: #{e.message}")
    raise
  end

  def self.send_fcm_notification(tokens, title, body, data = {})
    return if tokens.empty?

    valid_tokens = tokens.select { |t| t&.match?(/\A[a-zA-Z0-9:_\-\.]{100,200}\z/) }
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
        Rails.logger.info("FCM notification sent to token: #{token}")
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
    send_movie_notification(movie, "New Movie Added", "is now available")
  end

  def self.send_updated_movie_notification(movie)
    send_movie_notification(movie, "Movie Updated", "has been updated")
  end

  def self.send_deleted_movie_notification(movie)
    send_movie_notification(movie, "Movie Removed", "is no longer available")
  end

  def self.send_subscription_notification(user, plan_type)
    return unless user.device_token

    send_fcm_notification(
      [user.device_token],
      "Subscription Activated!",
      "Your #{plan_type.capitalize} subscription has been successfully activated.",
      {
        plan_type: plan_type,
        subscription_id: user.subscription&.stripe_subscription_id,
        action: "subscription_activated"
      }
    )
  end

  def self.send_payment_failure_notification(user)
    return unless user.device_token

    send_fcm_notification(
      [user.device_token],
      "Payment Failed",
      "There was an issue with your subscription payment. Please update your payment method.",
      {
        type: "payment_failure",
        action: "payment_failed"
      }
    )
  end

  def self.send_cancellation_notification(user)
    return unless user.device_token

    send_fcm_notification(
      [user.device_token],
      "Subscription Canceled",
      "Your subscription has been canceled. You are now on the free plan.",
      {
        type: "subscription_cancellation",
        action: "subscription_canceled"
      }
    )
  end

  private

  def self.send_movie_notification(movie, title_prefix, body_action)
    users = movie.premium? ? User.with_active_subscription : User.all
    device_tokens = users.where.not(device_token: nil).pluck(:device_token)

    return if device_tokens.empty?

    device_tokens.each_slice(500) do |token_batch|
      send_fcm_notification(
        token_batch,
        "#{title_prefix}",
        "#{movie.title} #{body_action}#{movie.premium? ? ' for premium users' : ''}!",
        {
          movie_id: movie.id.to_s,
          title: movie.title,
          premium: movie.premium.to_s,
          action: title_prefix.downcase.gsub(" ", "_")
        }
      )
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