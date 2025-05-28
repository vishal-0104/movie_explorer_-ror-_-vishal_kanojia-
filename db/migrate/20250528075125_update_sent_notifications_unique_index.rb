class UpdateSentNotificationsUniqueIndex < ActiveRecord::Migration[7.2]
  def change
    remove_index :sent_notifications, name: "index_sent_notifications_unique"

    add_index :sent_notifications, 
              [:user_id, :movie_id, :notification_type, :action, :channel], 
              unique: true, 
              name: "index_sent_notifications_unique"
  end
end