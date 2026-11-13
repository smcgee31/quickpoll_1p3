class LtiPlatform < ApplicationRecord
  has_many :lti_registrations, dependent: :destroy
  has_many :lti_users, dependent: :destroy
  has_many :lti_contexts, dependent: :destroy

  validates :issuer, :name, :auth_endpoint, :token_endpoint, :jwks_uri, presence: true
  validates :issuer, uniqueness: true
end
