class CreateBlacklistedTokens < ActiveRecord::Migration[7.2]
  def change
    create_table :blacklisted_tokens do |t|
      t.string :jti, null: false              # renamed from token to jti
      t.references :user, null: false, foreign_key: true
      t.datetime :expires_at, null: false     # added new column
      t.timestamps
    end

    add_index :blacklisted_tokens, :jti, unique: true
    add_index :blacklisted_tokens, :expires_at
  end
end
