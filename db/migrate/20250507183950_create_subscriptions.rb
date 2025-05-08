class CreateSubscriptions < ActiveRecord::Migration[7.2]
  def change
    create_table :subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :plan_type, null: false
      t.string :status, null: false
      t.datetime :start_date, null: false
      t.datetime :end_date
      t.timestamps
    end
  end
end