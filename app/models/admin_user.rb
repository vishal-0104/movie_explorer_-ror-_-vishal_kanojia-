class AdminUser < ApplicationRecord
  devise :database_authenticatable, 
         :recoverable, :rememberable, :validatable

         def self.ransackable_attributes(auth_object = nil)
          ["id", "email", "created_at", "updated_at"]
         end
end
