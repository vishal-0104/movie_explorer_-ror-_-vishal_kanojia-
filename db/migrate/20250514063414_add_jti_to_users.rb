class AddJtiToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :jti, :string
    add_index :users, :jti, unique: true

    User.find_each do |user|
      user.update_column(:jti, SecureRandom.uuid)
    end

    change_column_null :users, :jti, false
  end
end
