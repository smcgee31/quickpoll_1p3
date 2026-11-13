require "rails_helper"

# Step D2, part 2. Decide whether a launch is real. This is the heart of LTI 1.3.
#
# In 1.1 the check was one HMAC signature with a shared secret. In 1.3 Canvas signs an id_token (a JWT)
# with a private key, and we check it with the public key of Canvas. A JWT is three base64 parts,
# header.payload.signature. The payload holds the "claims": facts about the launch.
#
# What to build: app/services/lti1p3/launch_verifier.rb
#   verifier = Lti1p3::LaunchVerifier.new(id_token: params[:id_token], state: params[:state])
#   verifier.call        # true or false. It never raises for a bad launch.
#   verifier.error       # nil, or a symbol from the list below
#   verifier.claims      # the claims Hash (string keys) after a good call
#   verifier.registration, verifier.deployment   # the rows the launch matched, after a good call
#
# The state comes first. It tells you which registration this launch belongs to, so you know which
# platform and which keys to use. Do the checks in this order:
#   1. state blank                      :missing_state
#   2. id_token blank                   :missing_id_token
#   3. no LtiLaunchState with that state     :unknown_state
#   4. state already used (used_at set)      :state_used
#   5. state older than 10 minutes           :state_expired   (9 minutes is fine)
#   6. keys: Lti1p3::PlatformKeys.fetch(registration.lti_platform). If it raises Unavailable:
#                                       :keys_unavailable
#   7. the token: JSON::JWT.decode(id_token, JSON::JWK::Set.new(keys), [:RS256])
#        * not a JWT at all             :malformed_token   (JSON::JWT::InvalidFormat)
#        * any other JSON::JWT::Exception  :bad_signature
#      Pass [:RS256] as the third argument. It states the rule: only RS256 counts. A token with
#      "alg: none", or one "signed" with HS256 and the public key as the secret, must fail. The json-jwt
#      gem already refuses both when it gets a key set, so the specs for them guard against a later
#      change. The header "kid" picks the key.
#   8. the claims, in this order:
#        exp, iat, sub, or the context claim missing  :missing_claim
#        iss is not the issuer of the platform        :wrong_issuer
#        aud does not hold the client_id of the registration (aud is a String or an Array)
#                                                     :wrong_audience
#        exp is now or earlier                        :expired
#        iat is more than 60 seconds in the future    :issued_in_future
#        nonce is not the nonce saved with the state  :wrong_nonce
#        message_type claim is not "LtiResourceLinkRequest"  :unsupported_message_type
#        version claim is not "1.3.0"                 :unsupported_version
#        deployment_id claim is not a deployment of THIS registration   :unknown_deployment
#   9. last, mark the state used: set used_at. Do it so two requests at the same moment cannot both win.
#      A good way: LtiLaunchState.where(id: ..., used_at: nil).update_all(used_at: Time.current) returns
#      1 for the one winner. If it returns 0, the error is :state_used.
#
# A failed check never marks the state used. Only a launch that passed every check uses it up.
RSpec.describe "Lti1p3::LaunchVerifier" do
  include_context "with 1.3 launches"

  def verifier_for(token = sign_id_token, state: "state-1")
    Lti1p3::LaunchVerifier.new(id_token: token, state: state)
  end

  def expect_refused(verifier, error)
    expect(verifier.call).to be(false)
    expect(verifier.error).to eq(error)
  end

  def base64url(text)
    Base64.urlsafe_encode64(text, padding: false)
  end

  describe "a good launch" do
    it "is accepted" do
      verifier = verifier_for

      expect(verifier.call).to be(true)
      expect(verifier.error).to be_nil
    end

    it "gives back the claims, the registration, and the deployment" do
      verifier = verifier_for
      verifier.call

      expect(verifier.claims["sub"]).to eq("lti-user-1")
      expect(verifier.claims[claim("context")]).to include("id" => "context-abc")
      expect(verifier.registration).to eq(registration)
      expect(verifier.deployment).to eq(deployment)
    end

    it "marks the state used" do
      verifier_for.call

      expect(launch_state.reload.used_at).to be_within(1.second).of(now)
    end

    it "asks for the keys of the platform of the registration" do
      verifier_for.call

      expect(Lti1p3::PlatformKeys).to have_received(:fetch).with(platform)
    end

    it "accepts an aud that is an Array holding the client_id" do
      token = sign_id_token(launch_claims("aud" => [ "other", registration.client_id ]))

      expect(verifier_for(token).call).to be(true)
    end

    it "uses the kid in the header to pick the key when the platform has two" do
      other = OpenSSL::PKey::RSA.generate(2048)
      other_jwk = JSON::JWK.new(other.public_key, kid: "old-key", use: "sig", alg: "RS256").as_json.deep_stringify_keys
      allow(Lti1p3::PlatformKeys).to receive(:fetch).with(platform).and_return([ other_jwk, platform_jwk ])

      expect(verifier_for.call).to be(true)
    end

    it "accepts a state that is 9 minutes old" do
      launch_state.update!(created_at: 9.minutes.ago)

      expect(verifier_for.call).to be(true)
    end

    it "accepts an iat 30 seconds in the future, for clocks that differ a little" do
      token = sign_id_token(launch_claims("iat" => now.to_i + 30))

      expect(verifier_for(token).call).to be(true)
    end
  end

  describe "the state" do
    it "refuses a blank state" do
      expect_refused(verifier_for(state: ""), :missing_state)
      expect_refused(verifier_for(state: nil), :missing_state)
    end

    it "refuses a blank id_token" do
      expect_refused(verifier_for(""), :missing_id_token)
      expect_refused(verifier_for(nil), :missing_id_token)
    end

    it "refuses a state we never made" do
      expect_refused(verifier_for(state: "never-made"), :unknown_state)
    end

    it "refuses a state that was already used" do
      launch_state.update!(used_at: 1.minute.ago)

      expect_refused(verifier_for, :state_used)
    end

    it "refuses a state older than 10 minutes" do
      launch_state.update!(created_at: 11.minutes.ago)

      expect_refused(verifier_for, :state_expired)
    end

    it "refuses the same launch the second time" do
      expect(verifier_for.call).to be(true)

      expect_refused(verifier_for, :state_used)
    end

    it "refuses a state that was made for another registration" do
      other = create(:lti_registration, lti_platform: platform, client_id: "10000000000002")
      create(:lti_launch_state, lti_registration: other, state: "state-other", nonce: "nonce-1")

      expect_refused(verifier_for(state: "state-other"), :wrong_audience)
    end

    it "leaves the state unused when a check fails" do
      verifier = verifier_for(sign_id_token(launch_claims("nonce" => "wrong")))

      expect_refused(verifier, :wrong_nonce)
      expect(launch_state.reload.used_at).to be_nil
    end
  end

  describe "the token" do
    it "refuses text that is not a JWT" do
      expect_refused(verifier_for("not-a-token"), :malformed_token)
    end

    it "refuses a token signed with another key" do
      token = sign_id_token(key: OpenSSL::PKey::RSA.generate(2048))

      expect_refused(verifier_for(token), :bad_signature)
    end

    it "refuses a token with a kid the platform does not have" do
      expect_refused(verifier_for(sign_id_token(kid: "no-such-key")), :bad_signature)
    end

    it "refuses a token with no signature (alg none)" do
      header = base64url({ alg: "none", typ: "JWT", kid: platform_kid }.to_json)
      payload = base64url(launch_claims.to_json)

      expect_refused(verifier_for("#{header}.#{payload}."), :bad_signature)
    end

    it "refuses a token signed with HS256 and the public key as the secret" do
      jwt = JSON::JWT.new(launch_claims)
      jwt.kid = platform_kid
      token = jwt.sign(LTI1P3_PLATFORM_KEY.public_key.to_pem, :HS256).to_s

      expect_refused(verifier_for(token), :bad_signature)
    end

    it "refuses a token whose payload changed after it was signed" do
      header, _payload, signature = sign_id_token.split(".")
      forged = base64url(launch_claims("sub" => "someone-else").to_json)

      expect_refused(verifier_for("#{header}.#{forged}.#{signature}"), :bad_signature)
    end

    it "refuses the launch when the keys of the platform cannot be fetched" do
      allow(Lti1p3::PlatformKeys).to receive(:fetch).and_raise(Lti1p3::PlatformKeys::Unavailable)

      expect_refused(verifier_for, :keys_unavailable)
    end
  end

  describe "the claims" do
    it "refuses a token from another issuer" do
      expect_refused(verifier_for(sign_id_token(launch_claims("iss" => "https://evil.example.test"))), :wrong_issuer)
    end

    it "refuses a token for another audience" do
      expect_refused(verifier_for(sign_id_token(launch_claims("aud" => "99999"))), :wrong_audience)
      expect_refused(verifier_for(sign_id_token(launch_claims("aud" => [ "99999" ]))), :wrong_audience)
    end

    it "refuses an expired token" do
      expect_refused(verifier_for(sign_id_token(launch_claims("exp" => now.to_i - 1))), :expired)
      expect_refused(verifier_for(sign_id_token(launch_claims("exp" => now.to_i))), :expired)
    end

    it "refuses a token issued more than 60 seconds in the future" do
      expect_refused(verifier_for(sign_id_token(launch_claims("iat" => now.to_i + 120))), :issued_in_future)
    end

    it "refuses a token with another nonce" do
      expect_refused(verifier_for(sign_id_token(launch_claims("nonce" => "nonce-2"))), :wrong_nonce)
    end

    it "refuses a message type that is not a resource link launch" do
      token = sign_id_token(launch_claims(claim("message_type") => "LtiDeepLinkingRequest"))

      expect_refused(verifier_for(token), :unsupported_message_type)
    end

    it "refuses an LTI version other than 1.3.0" do
      expect_refused(verifier_for(sign_id_token(launch_claims(claim("version") => "1.2.0"))), :unsupported_version)
    end

    it "refuses a deployment id we do not know" do
      token = sign_id_token(launch_claims(claim("deployment_id") => "9:unknown"))

      expect_refused(verifier_for(token), :unknown_deployment)
    end

    it "refuses the deployment of another registration" do
      other = create(:lti_registration, lti_platform: platform, client_id: "10000000000002")
      create(:lti_deployment, lti_registration: other, deployment_id: "2:other")
      token = sign_id_token(launch_claims(claim("deployment_id") => "2:other"))

      expect_refused(verifier_for(token), :unknown_deployment)
    end

    it "refuses a token with no deployment id" do
      expect_refused(verifier_for(sign_id_token(launch_claims.except(claim("deployment_id")))), :unknown_deployment)
    end

    [ "exp", "iat", "sub" ].each do |name|
      it "refuses a token with no #{name}" do
        expect_refused(verifier_for(sign_id_token(launch_claims.except(name))), :missing_claim)
      end
    end

    it "refuses a blank sub" do
      expect_refused(verifier_for(sign_id_token(launch_claims("sub" => ""))), :missing_claim)
    end

    it "refuses a token with no course (context claim)" do
      expect_refused(verifier_for(sign_id_token(launch_claims.except(claim("context")))), :missing_claim)
    end

    it "refuses a context claim with no id" do
      token = sign_id_token(launch_claims(claim("context") => { "title" => "No id" }))

      expect_refused(verifier_for(token), :missing_claim)
    end
  end
end
