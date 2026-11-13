class LtiLaunchState < ApplicationRecord
  belongs_to :lti_registration
  validates :state, :nonce, presence: true
  validates :state, uniqueness: true
end
