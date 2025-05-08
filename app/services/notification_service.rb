require 'httparty'
require 'googleauth'

class NotificationService
  # Fetches OAuth 2.0 access token using Service Account JSON
  def self.get_access_token
    credentials = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open(Rails.root.join('config/credentials/fcm-service-account.json')),
      scope: 'https://www.googleapis.com/auth/firebase.messaging'
    )
    credentials.fetch_access_token!['access_token']
  end

  # Sends FCM notification to a single device token
  def self.send_fcm_notification(token, title, body)
    headers = {
      'Authorization': "Bearer #{get_access_token}",
      'Content-Type': 'application/json'
    }
    body = {
      message: {
        token: token,
        notification: {
          title: title,
          body: body
        }
      }
    }.to_json

    response = HTTParty.post(
      "https://fcm.googleapis.com/v1/projects/#{ENV['FCM_PROJECT_ID']}/messages:send",
      headers: headers,
      body: body
    )
    Rails.logger.info "FCM Response: #{response.body}"
    response
  end

  # Sends notification to all users with device tokens when a new movie is added
  def self.send_new_movie_notification(movie)
    User.where.not(device_token: nil).find_each do |user|
      send_fcm_notification(
        user.device_token,
        'New Movie Added',
        "#{movie.title} is now available!"
      )
    end
  end
end