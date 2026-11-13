class LtiRegistration < ApplicationRecord
  belongs_to :lti_platform
  has_many :lti_deployments, dependent: :destroy
  has_many :lti_launch_states, dependent: :destroy
  validates :client_id, presence: true, uniqueness: { scope: :lti_platform_id }

  before_validation :generate_keys, on: :create

  def public_jwk
    JSON::JWK.new(OpenSSL::PKey::RSA.new(public_key), kid:, use: "sig", alg: "RS256").as_json
  end

  private

  # Note: The private key is stored as plain text in the database.
  # A real app would encrypt it with Rails `encrypts`, or keeps it in a secrets store.
  def generate_keys
    return if private_key.present?

    key = OpenSSL::PKey::RSA.generate(2048)
    self.private_key = key.to_pem
    self.public_key = key.public_key.to_pem
    self.kid = SecureRandom.uuid
  end
end
