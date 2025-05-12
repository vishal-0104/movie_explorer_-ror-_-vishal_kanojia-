class UpdateBlacklistedTokens < ActiveRecord::Migration[7.2]
  def change
    # Rename the token column to jti
    rename_column :blacklisted_tokens, :token, :jti

    # Add expires_at column (allow null temporarily)
    add_column :blacklisted_tokens, :expires_at, :datetime

    # Backfill expires_at with a default value (e.g., created_at)
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE blacklisted_tokens
          SET expires_at = created_at
          WHERE expires_at IS NULL;
        SQL
      end
    end

    # Set expires_at as not null
    change_column_null :blacklisted_tokens, :expires_at, false

    # Remove the old index on token (now jti) if it exists
    remove_index :blacklisted_tokens, name: :index_blacklisted_tokens_on_token, if_exists: true

    # Add index on jti (unique) only if it doesn't exist
    unless index_exists?(:blacklisted_tokens, :jti, name: :index_blacklisted_tokens_on_jti)
      add_index :blacklisted_tokens, :jti, unique: true, name: :index_blacklisted_tokens_on_jti
    end

    # Add index on expires_at
    add_index :blacklisted_tokens, :expires_at, name: :index_blacklisted_tokens_on_expires_at
  end
end