class BlacklistedToken < ApplicationRecord
  self.table_name = 'blacklisted_tokens'

  belongs_to :user

  validates :jti, presence: true, uniqueness: true
  validates :expires_at, presence: true

  def self.revoked?(payload)
    return false if payload['jti'].nil?

    blacklisted_token = find_by(jti: payload['jti'], user_id: payload['user_id'])
    return false unless blacklisted_token

    if blacklisted_token.expires_at < Time.current
      blacklisted_token.destroy
      false
    else
      true
    end
  end

  def self.revoke(payload)
    jti = payload['jti']
    user_id = payload['user_id']
    return if jti.nil? || user_id.nil? || exists?(jti: jti)

    user = User.find_by(id: user_id)
    if user
      # Delegate to User.revoke_jwt for Devise compatibility
      User.revoke_jwt(payload, user)
    else
      Rails.logger.error "BlacklistedToken.revoke: User not found for user_id: #{user_id}"
      raise ActiveRecord::RecordNotFound, "User not found for user_id: #{user_id}"
    end
  rescue StandardError => e
    Rails.logger.error "BlacklistedToken Revoke Error: #{e.message}"
    raise
  end

  def self.cleanup_expired
    where('expires_at < ?', Time.current).destroy_all
  end
end