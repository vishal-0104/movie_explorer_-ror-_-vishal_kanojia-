class AddPendingToSubscriptionStatus < ActiveRecord::Migration[7.2]
  def change
    change_column :subscriptions, :status, :string, null: false, default: 'pending'
  end
end
