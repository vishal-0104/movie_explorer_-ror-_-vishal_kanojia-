class AddStripeCustomerIdToSubscriptions < ActiveRecord::Migration[7.2]
  def change
    add_column :subscriptions, :stripe_customer_id, :string
  end
end
