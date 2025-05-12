class AddUniqueIndexAndStripeSubscriptionIdToSubscriptions < ActiveRecord::Migration[7.2]
  def change
    
    add_column :subscriptions, :stripe_subscription_id, :string


    remove_index :subscriptions, :user_id, name: :index_subscriptions_on_user_id if index_exists?(:subscriptions, :user_id, name: :index_subscriptions_on_user_id)


    add_index :subscriptions, :user_id, unique: true
  end
end