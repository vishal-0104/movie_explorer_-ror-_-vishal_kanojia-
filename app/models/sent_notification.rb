class SentNotification < ApplicationRecord
  belongs_to :user

  validates :user_id, presence: true
  validates :notification_type, presence: true
  validates :action, presence: true
  validates :channel, presence: true, inclusion: { in: %w[fcm whatsapp] }
  validates :sent_at, presence: true

  validates :user_id, uniqueness: { 
    scope: [:movie_id, :notification_type, :channel, :action], 
    message: "Notification already sent for this user, movie, type, channel, and action" 
  }
end