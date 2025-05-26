class CreateSentNotifications < ActiveRecord::Migration[7.2]
  def change
    create_table :sent_notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :movie_id
      t.string :notification_type
      t.string :action
      t.string :channel
      t.datetime :sent_at, null: false
      t.timestamps
    end
    add_index :sent_notifications, [:user_id, :movie_id, :notification_type, :channel], unique: true, name: 'index_sent_notifications_unique'
  end
end