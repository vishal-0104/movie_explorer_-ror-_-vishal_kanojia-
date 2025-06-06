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

      user = users.first
      next unless user

      notification_params = {
        user_id: user.id,
        notification_type: data[:notification_type],
        action: data[:action],
        channel: 'fcm',
        movie_id: data[:movie_id]&.to_i
      }

      # Skip if notification already exists
      if SentNotification.exists?(notification_params)
        Rails.logger.info("Skipping FCM notification for token: #{token}, user ID: #{user.id} - Notification already sent")
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
        user.with_lock do
          SentNotification.create!(notification_params.merge(sent_at: Time.current))
        end
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
      user = User.find_by(id: user_id)
      next unless user

      notification_params = {
        user_id: user_id,
        notification_type: template_data['notification_type'] || template_name,
        action: template_data['action'],
        channel: 'whatsapp',
        movie_id: template_data['movie_id']&.to_i
      }

      # Skip if notification already exists
      if SentNotification.exists?(notification_params)
        Rails.logger.info("Skipping WhatsApp notification for number: #{number}, user ID: #{user_id} - Notification already sent")
        next
      end

      begin
        response = client.messages.create(
          from: from_number,
          to: "whatsapp:#{number}",
          content_sid: content_sid,
          content_variables: template_data.to_json
        )
        Rails.logger.info("WhatsApp notification sent to #{number}: SID #{response.sid}")
        user.with_lock do
          SentNotification.create!(notification_params.merge(sent_at: Time.current))
        end
        responses << response
      rescue Twilio::REST::RestError => e
        Rails.logger.error("WhatsApp notification failed for #{number}: #{e.message} (Code: #{e.code})")
        handle_twilio_error(e, number, user_id)
      end
    end
    responses
  end

  def self.send_whatsapp_opt_in_sms(mobile_number, user_id)
    return unless mobile_number && user_id

    client = Twilio::REST::Client.new(ENV['TWILIO_ACCOUNT_SID'], ENV['TWILIO_AUTH_TOKEN'])
    from_number = ENV['TWILIO_WHATSAPP_NUMBER'] || 'whatsapp:+14155238886'

    user = User.find_by(id: user_id)
    return unless user

    notification_params = {
      user_id: user_id,
      notification_type: 'whatsapp_opt_in',
      action: 'whatsapp_opt_in',
      channel: 'whatsapp'
    }

    # Skip if notification already exists
    if SentNotification.exists?(notification_params)
      Rails.logger.info("Skipping WhatsApp opt-in SMS for number: #{mobile_number}, user ID: #{user_id} - Notification already sent")
      return
    end

    template_data = {
      '1' => 'Please reply with "YES" to opt in to WhatsApp notifications.',
      'action' => 'whatsapp_opt_in',
      'notification_type' => 'whatsapp_opt_in'
    }

    begin
      response = client.messages.create(
        from: from_number,
        to: "whatsapp:#{mobile_number}",
        content_sid: ENV['TWILIO_OPT_IN_CONFIRMATION_CONTENT_SID'],
        content_variables: template_data.to_json
      )
      Rails.logger.info("WhatsApp opt-in SMS sent to #{mobile_number}: SID #{response.sid}")
      user.with_lock do
        SentNotification.create!(notification_params.merge(sent_at: Time.current))
      end
      response
    rescue Twilio::REST::RestError => e
      Rails.logger.error("WhatsApp opt-in SMS failed for #{mobile_number}: #{e.message} (Code: #{e.code})")
      handle_twilio_error(e, mobile_number, user_id)
      nil
    end
  end

  def self.send_subscription_notification(user, plan_type)
    notification_type = 'subscription'
    action = 'subscription_activated'

    if user.device_token
      send_fcm_notification(
        [user.device_token],
        "Subscription Activated!",
        "Your #{plan_type.capitalize} subscription has been successfully activated.",
        {
          plan_type: plan_type,
          subscription_id: user.subscription&.stripe_subscription_id || '',
          action: action,
          notification_type: notification_type
        }
      )
    end

    if user.mobile_number
      template_data = {
        '1' => plan_type.capitalize,
        '2' => user.subscription&.stripe_subscription_id || 'N/A',
        'action' => action,
        'notification_type' => notification_type
      }
      send_whatsapp_notification(
        { user.mobile_number => user.id },
        'subscription_notification',
        template_data,
        ENV['TWILIO_SUBSCRIPTION_CONTENT_SID']
      )
    end
  end

  def self.send_payment_failure_notification(user)
    notification_type = 'payment'
    action = 'payment_failed'

    if user.device_token
      send_fcm_notification(
        [user.device_token],
        "Payment Failed",
        "There was an issue with your subscription payment. Please update your payment method.",
        {
          type: 'payment_failure',
          action: action,
          notification_type: notification_type
        }
      )
    end

    if user.mobile_number
      template_data = {
        '1' => 'Please update your payment method',
        'action' => action,
        'notification_type' => notification_type
      }
      send_whatsapp_notification(
        { user.mobile_number => user.id },
        'payment_failure_notification',
        template_data,
        ENV['TWILIO_PAYMENT_FAILURE_CONTENT_SID']
      )
    end
  end

  def self.send_cancellation_notification(user)
    notification_type = 'subscription'
    action = 'subscription_cancelled'

    if user.device_token
      send_fcm_notification(
        [user.device_token],
        "Subscription Cancelled",
        "Your subscription has been cancelled. You are now on the free plan.",
        {
          type: 'subscription_cancellation',
          action: action,
          notification_type: notification_type
        }
      )
    end

    if user.mobile_number
      template_data = {
        '1' => 'You are now on the free plan',
        'action' => action,
        'notification_type' => notification_type
      }
      send_whatsapp_notification(
        { user.mobile_number => user.id },
        'cancellation_notification',
        template_data,
        ENV['TWILIO_CANCELLATION_CONTENT_SID']
      )
    end
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

  private

  def self.send_movie_notification(movie, title_prefix, body_action, action)
    users = movie.premium? ? User.with_active_subscription : User.all
    device_tokens = users.where.not(device_token: nil).pluck(:device_token, :id).to_h
    mobile_numbers = users.where.not(mobile_number: nil).pluck(:mobile_number, :id).to_h

    return if device_tokens.empty? && mobile_numbers.empty?

    base_url = ENV['APP_BASE_URL'] || 'https://yourapp.com'
    movie_url = "#{base_url}/movies/#{movie.id}"

    device_tokens.each_slice(500) do |token_batch|
      token_batch.each do |token, user_id|
        send_fcm_notification(
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
      end
    end

    mobile_numbers.each_slice(500) do |number_batch|
      number_batch.each do |number, user_id|
        template_data = {
          '1' => movie.title,
          '2' => body_action + (movie.premium? ? ' for premium users' : ''),
          '3' => movie_url,
          'movie_id' => movie.id.to_s,
          'action' => action,
          'notification_type' => 'movie'
        }
        send_whatsapp_notification(
          { number => user_id },
          'movie_notification',
          template_data,
          ENV['TWILIO_MOVIE_CONTENT_SID']
        )
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