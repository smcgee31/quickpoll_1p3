class LtiPlatform < ApplicationRecord
  has_many :lti_registrations, dependent: :destroy
  validates :issuer, :name, :auth_endpoint, :token_endpoint, :jwks_uri, presence: true
  validates :issuer, uniqueness: true
end
