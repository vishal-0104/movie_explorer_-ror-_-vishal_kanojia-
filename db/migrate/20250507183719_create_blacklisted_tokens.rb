class CreateBlacklistedTokens < ActiveRecord::Migration[7.2]
  def change
    create_table :blacklisted_tokens do |t|
      t.string :token, null: false
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :blacklisted_tokens, :token, unique: true
  end
end