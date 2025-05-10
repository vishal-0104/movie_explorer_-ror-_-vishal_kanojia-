class BlacklistedToken < ApplicationRecord
  self.table_name = 'blacklisted_tokens'

  belongs_to :user

  validates :jti, presence: true, uniqueness: true
  validates :expires_at, presence: true
end