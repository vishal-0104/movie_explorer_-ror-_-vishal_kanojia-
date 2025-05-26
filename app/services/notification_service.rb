require 'httparty'
require 'googleauth'
require 'twilio-ruby'

class NotificationService
  ACCESS_TOKEN_CACHE_KEY = 'fcm_access_token'.freeze
  ACCESS_TOKEN_EXPIRY = 55.minutes
  FCM_TOKEN_REGEX = /\A[a-zA-Z0-9:_\-\.=]{50,300}\z/.freeze

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
    Rails.logger.error("Failed to fetch FCM access token for project #{ENV['FCM_PROJECT_ID']}: #{e.message}, Backtrace: #{e.backtrace.join("\n")}")
    nil
  end

  def self.send_fcm_notification(tokens, title, body, data = {})
    return if tokens.blank?

    valid_tokens = tokens.uniq.select { |t| t.present? && t.match?(FCM_TOKEN_REGEX) }
    invalid_tokens = tokens - valid_tokens
    invalid_tokens.each do |token|
      Rails.logger.warn("Invalid FCM token detected: #{token}")
      User.where(device_token: token).each do |user|
        Rails.logger.info("Removing invalid FCM token: #{token} for user ID: #{user.id}")
        user.update(device_token: nil)
      end
    end

    return if valid_tokens.empty?

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
      users = User.where(device_token: token)
      user_ids = users.pluck(:id).join(', ')
      if users.count > 1
        Rails.logger.warn("Duplicate FCM token #{token} for user IDs: #{user_ids}")
        users.each { |user| user.update(device_token: nil) }
        next
      end

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
        Rails.logger.info("FCM notification sent to token: #{token}, user IDs: #{user_ids}, title: #{title}")
      else
        Rails.logger.error("FCM notification failed for token: #{token}, user IDs: #{user_ids}, status: #{response.code}, body: #{response.body}")
      end
      responses << response
    end

    handle_response_errors(responses, valid_tokens)
    responses
  rescue StandardError => e
    Rails.logger.error("FCM notification error: #{e.message}, Backtrace: #{e.backtrace.join("\n")}")
    nil
  end

  def self.send_whatsapp_notification(to_numbers, template_name, template_data, content_sid)
    return if to_numbers.empty?

    client = Twilio::REST::Client.new(ENV['TWILIO_ACCOUNT_SID'], ENV['TWILIO_AUTH_TOKEN'])
    from_number = ENV['TWILIO_WHATSAPP_NUMBER'] || 'whatsapp:+14155238886'

    responses = []
    to_numbers.each do |number, user_id|
      begin
        response = client.messages.create(
          from: from_number,
          to: "whatsapp:#{number}",
          content_sid: content_sid,
          content_variables: template_data.to_json
        )
        Rails.logger.info("WhatsApp notification sent to #{number}: SID #{response.sid}")
        responses << response
      rescue Twilio::REST::RestError => e
        Rails.logger.error("WhatsApp notification failed for #{number}: #{e.message} (Code: #{e.code})")
        handle_twilio_error(e, number, user_id)
      end
    end
    responses
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
    # FCM
    if user.device_token
      unless SentNotification.exists?(
        user_id: user.id,
        notification_type: 'subscription',
        action: 'subscription_activated',
        channel: 'fcm'
      )
        response = send_fcm_notification(
          [user.device_token],
          "Subscription Activated!",
          "Your #{plan_type.capitalize} subscription has been successfully activated.",
          {
            plan_type: plan_type,
            subscription_id: user.subscription&.stripe_subscription_id || '',
            action: 'subscription_activated',
            notification_type: 'subscription'
          }
        )
        if response&.any?(&:success?)
          SentNotification.create!(
            user_id: user.id,
            notification_type: 'subscription',
            action: 'subscription_activated',
            channel: 'fcm',
            sent_at: Time.current
          )
        end
      end
    end

    # WhatsApp
    if user.mobile_number
      unless SentNotification.exists?(
        user_id: user.id,
        notification_type: 'subscription',
        action: 'subscription_activated',
        channel: 'whatsapp'
      )
        template_data = {
          '1' => plan_type.capitalize,
          '2' => user.subscription&.stripe_subscription_id || 'N/A',
          'action' => 'subscription_activated'
        }
        response = send_whatsapp_notification(
          { user.mobile_number => user.id },
          'subscription_notification',
          template_data,
          ENV['TWILIO_SUBSCRIPTION_CONTENT_SID']
        )
        if response&.any? { |r| r.status == 'sent' || r.status == 'queued' }
          SentNotification.create!(
            user_id: user.id,
            notification_type: 'subscription',
            action: 'subscription_activated',
            channel: 'whatsapp',
            sent_at: Time.current
          )
        end
      end
    end
  end

  def self.send_payment_failure_notification(user)
    # FCM
    if user.device_token
      unless SentNotification.exists?(
        user_id: user.id,
        notification_type: 'payment',
        action: 'payment_failed',
        channel: 'fcm'
      )
        response = send_fcm_notification(
          [user.device_token],
          "Payment Failed",
          "There was an issue with your subscription payment. Please update your payment method.",
          {
            type: 'payment_failure',
            action: 'payment_failed',
            notification_type: 'payment'
          }
        )
        if response&.any?(&:success?)
          SentNotification.create!(
            user_id: user.id,
            notification_type: 'payment',
            action: 'payment_failed',
            channel: 'fcm',
            sent_at: Time.current
          )
        end
      end
    end

    # WhatsApp
    if user.mobile_number
      unless SentNotification.exists?(
        user_id: user.id,
        notification_type: 'payment',
        action: 'payment_failed',
        channel: 'whatsapp'
      )
        template_data = {
          '1' => 'Please update your payment method',
          'action' => 'payment_failed'
        }
        response = send_whatsapp_notification(
          { user.mobile_number => user.id },
          'payment_failure_notification',
          template_data,
          ENV['TWILIO_PAYMENT_FAILURE_CONTENT_SID']
        )
        if response&.any? { |r| r.status == 'sent' || r.status == 'queued' }
          SentNotification.create!(
            user_id: user.id,
            notification_type: 'payment',
            action: 'payment_failed',
            channel: 'whatsapp',
            sent_at: Time.current
          )
        end
      end
    end
  end

  def self.send_cancellation_notification(user)
    # FCM
    if user.device_token
      unless SentNotification.exists?(
        user_id: user.id,
        notification_type: 'subscription',
        action: 'subscription_cancelled',
        channel: 'fcm'
      )
        response = send_fcm_notification(
          [user.device_token],
          "Subscription Cancelled",
          "Your subscription has been cancelled. You are now on the free plan.",
          {
            type: 'subscription_cancellation',
            action: 'subscription_cancelled',
            notification_type: 'subscription'
          }
        )
        if response&.any?(&:success?)
          SentNotification.create!(
            user_id: user.id,
            notification_type: 'subscription',
            action: 'subscription_cancelled',
            channel: 'fcm',
            sent_at: Time.current
          )
        end
      end
    end

    # WhatsApp
    if user.mobile_number
      unless SentNotification.exists?(
        user_id: user.id,
        notification_type: 'subscription',
        action: 'subscription_cancelled',
        channel: 'whatsapp'
      )
        template_data = {
          '1' => 'You are now on the free plan',
          'action' => 'subscription_cancelled'
        }
        response = send_whatsapp_notification(
          { user.mobile_number => user.id },
          'cancellation_notification',
          template_data,
          ENV['TWILIO_CANCELLATION_CONTENT_SID']
        )
        if response&.any? { |r| r.status == 'sent' || r.status == 'queued' }
          SentNotification.create!(
            user_id: user.id,
            notification_type: 'subscription',
            action: 'subscription_cancelled',
            channel: 'whatsapp',
            sent_at: Time.current
          )
        end
      end
    end
  end

  private

  def self.send_movie_notification(movie, title_prefix, body_action, action)
    users = movie.premium? ? User.with_active_subscription : User.all
    device_tokens = users.where.not(device_token: nil).pluck(:device_token, :id).to_h
    mobile_numbers = users.where.not(mobile_number: nil).pluck(:mobile_number, :id).to_h

    return if device_tokens.empty? && mobile_numbers.empty?

    base_url = ENV['APP_BASE_URL'] || 'https://yourapp.com'
    movie_url = "#{base_url}/movies/#{movie.id}"

    # FCM notifications
    device_tokens.each_slice(500) do |token_batch|
      token_batch.each do |token, user_id|
        next if SentNotification.exists?(
          user_id: user_id,
          movie_id: movie.id,
          notification_type: 'movie',
          action: action,
          channel: 'fcm'
        )

        response = send_fcm_notification(
          [token],
          title_prefix,
          "#{movie.title} #{body_action}#{movie.premium? ? ' for premium users' : ''}!",
          {
            movie_id: movie.id.to_s,
            title: movie.title,
            premium: movie.premium.to_s,
            action: action,
            notification_type: 'movie',
            url: movie_url
          }
        )

        if response&.any?(&:success?)
          SentNotification.create!(
            user_id: user_id,
            movie_id: movie.id,
            notification_type: 'movie',
            action: action,
            channel: 'fcm',
            sent_at: Time.current
          )
        end
      end
    end

    # WhatsApp notifications
    mobile_numbers.each_slice(500) do |number_batch|
      number_batch.each do |number, user_id|
        next if SentNotification.exists?(
          user_id: user_id,
          movie_id: movie.id,
          notification_type: 'movie',
          action: action,
          channel: 'whatsapp'
        )

        template_data = {
          '1' => movie.title,
          '2' => body_action + (movie.premium? ? ' for premium users' : ''),
          '3' => movie_url,
          'movie_id' => movie.id.to_s,
          'action' => action
        }

        response = send_whatsapp_notification(
          { number => user_id },
          'movie_notification',
          template_data,
          ENV['TWILIO_MOVIE_CONTENT_SID']
        )

        if response&.any? { |r| r.status == 'sent' || r.status == 'queued' }
          SentNotification.create!(
            user_id: user_id,
            movie_id: movie.id,
            notification_type: 'movie',
            action: action,
            channel: 'whatsapp',
            sent_at: Time.current
          )
        end
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

      users = User.where(device_token: token)
      user_ids = users.pluck(:id).join(', ')
      Rails.logger.warn("FCM error for token #{token}, user IDs: #{user_ids}: #{error_code} - #{error_message}#{fcm_error_code ? " (FCM errorCode: #{fcm_error_code})" : ''}")

      if fcm_error_code == 'UNREGISTERED' || error_message&.include?('NotRegistered') || error_message&.include?('InvalidRegistration')
        users.each do |user|
          Rails.logger.info("Removed invalid FCM token: #{token} for user ID: #{user.id}")
          user.update(device_token: nil)
          Rails.cache.increment('fcm_invalid_token_count')
        end
      end
    end
  end

  def self.handle_twilio_error(error, number, user_id)
    case error.code
    when 63003
      Rails.logger.warn("Number #{number} is not WhatsApp-enabled; removing for user #{user_id}")
      User.where(id: user_id).update_all(mobile_number: nil)
    when 63018
      Rails.logger.warn("Rate limit hit for #{number}: #{error.message}")
    when 63020
      Rails.logger.warn("Invitation not accepted in Meta Business Manager for #{number}")
    when 63016
      Rails.logger.warn("Attempted to send free-form message outside 24-hour session for #{number}")
    else
      Rails.logger.error("Unhandled Twilio error for #{number}: #{error.message} (Code: #{error.code})")
    end
  end
end