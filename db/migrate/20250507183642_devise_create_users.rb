class DeviseCreateUsers < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      t.string :email, null: false, default: ""
      t.string :encrypted_password, null: false, default: ""
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :mobile_number, null: false
      t.string :device_token
      t.integer :role, null: false, default: 0 # 0: user, 1: supervisor
      t.timestamps
    end
    add_index :users, :email, unique: true
    add_index :users, :mobile_number, unique: true
    add_index :users, :device_token, unique: true
  end
end