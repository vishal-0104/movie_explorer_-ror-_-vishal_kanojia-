class AddUniqueIndexAndStripeSubscriptionIdToSubscriptions < ActiveRecord::Migration[7.2]
  def change
    # Add the stripe_subscription_id column
    add_column :subscriptions, :stripe_subscription_id, :string

    # Remove the existing index if it exists
    remove_index :subscriptions, :user_id, name: :index_subscriptions_on_user_id if index_exists?(:subscriptions, :user_id, name: :index_subscriptions_on_user_id)

    # Add a new unique index
    add_index :subscriptions, :user_id, unique: true
  end
end