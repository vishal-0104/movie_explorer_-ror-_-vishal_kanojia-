class EnhanceSubscriptions < ActiveRecord::Migration[7.2]
  def change
    change_column_null :subscriptions, :status, false
    change_column_null :subscriptions, :plan_type, false
    add_index :subscriptions, :status
    add_index :subscriptions, :plan_type
  end
end