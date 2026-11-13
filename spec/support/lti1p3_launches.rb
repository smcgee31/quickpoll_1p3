# Shared setup for specs that need a 1.3 launch Canvas would accept.
#
# Canvas signs the id_token with its own private key. These specs sign with a key of their own, and
# they make Lti1p3::PlatformKeys.fetch return the matching public key. So no spec calls the network.
#
# Use it with: include_context "with 1.3 launches"
# Then: sign_id_token                                    # a good token
#       sign_id_token(launch_claims("nonce" => "other")) # one claim changed
#       sign_id_token(launch_claims.except("sub"))       # one claim removed
#       post "/lti/launch", params: { id_token: sign_id_token, state: "state-1" }
#
# The good token matches the rows this context creates: a platform, a registration, a deployment, and
# a saved login state. The state is "state-1" and its nonce is "nonce-1".

# One key for the whole run. A 2048-bit key takes about 100 ms to make, so do not make one per example.
LTI1P3_PLATFORM_KEY = OpenSSL::PKey::RSA.generate(2048) unless defined?(LTI1P3_PLATFORM_KEY)

RSpec.shared_context "with 1.3 launches" do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.at(1_800_000_000) }
  let(:public_base_url) { "http://quickpoll-test.example" }
  let(:platform_kid) { "platform-key-1" }
  let(:platform_jwk) do
    JSON::JWK.new(LTI1P3_PLATFORM_KEY.public_key, kid: platform_kid, use: "sig", alg: "RS256").as_json.deep_stringify_keys
  end
  let(:platform) { create(:lti_platform, issuer: "https://canvas.example.test") }
  let(:registration) { create(:lti_registration, lti_platform: platform, client_id: "10000000000001") }
  let(:deployment) { create(:lti_deployment, lti_registration: registration, deployment_id: "1:abc") }
  let(:launch_state) { create(:lti_launch_state, lti_registration: registration, state: "state-1", nonce: "nonce-1") }

  around do |example|
    original = Rails.configuration.x.public_base_url
    Rails.configuration.x.public_base_url = public_base_url
    travel_to(now) { example.run }
  ensure
    Rails.configuration.x.public_base_url = original
  end

  before do
    deployment
    launch_state
    allow(Lti1p3::PlatformKeys).to receive(:fetch).with(platform).and_return([ platform_jwk ])
  end

  def claim(name)
    "https://purl.imsglobal.org/spec/lti/claim/#{name}"
  end

  # The claims of a good launch from a teacher. Pass overrides to change claims.
  def launch_claims(overrides = {})
    {
      "iss" => platform.issuer,
      "aud" => registration.client_id,
      "sub" => "lti-user-1",
      "exp" => now.to_i + 3600,
      "iat" => now.to_i,
      "nonce" => launch_state.nonce,
      "name" => "Test Teacher 1",
      claim("message_type") => "LtiResourceLinkRequest",
      claim("version") => "1.3.0",
      claim("deployment_id") => deployment.deployment_id,
      claim("target_link_uri") => "#{public_base_url}/lti/launch",
      claim("roles") => [ "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor" ],
      claim("resource_link") => { "id" => "resource-link-1" },
      claim("context") => { "id" => "context-abc", "label" => "TC1", "title" => "Test Course 1" }
    }.merge(overrides)
  end

  def sign_id_token(claims = launch_claims, key: LTI1P3_PLATFORM_KEY, kid: platform_kid)
    jwt = JSON::JWT.new(claims)
    jwt.kid = kid
    jwt.sign(key, :RS256).to_s
  end
end
