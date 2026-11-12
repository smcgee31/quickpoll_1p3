require "rails_helper"

# Step A of the 1.3 build: who we trust, and our own keys.
#
# In 1.1 the tool knew one thing about Canvas: a key and a shared secret (lti_consumers).
# In 1.3 the tool knows three things, and each one is a table:
#
#   LtiPlatform      WHO sent the launch. Canvas, identified by its issuer URL, and the three URLs we
#                    need to talk to it: where to send the login redirect (auth_endpoint), where to ask
#                    for an access token (token_endpoint), and where its public keys are (jwks_uri).
#   LtiRegistration  OUR side of one install. In Canvas this is a developer key, and its number is the
#                    client_id. It holds the tool's own RSA key pair. There is no shared secret: Canvas
#                    signs launches with its private key and we check them with its public key. We sign
#                    things we send to Canvas with ours, and Canvas fetches our public key from our JWKS.
#   LtiDeployment    One place the tool was installed (an account or a course). Canvas names it with a
#                    deployment_id. Many deployments can share one registration.
#
# Platform has many registrations. Registration has many deployments.
#
# What to build (rails g model ..., then edit):
#   lti_platforms      issuer (unique), name, auth_endpoint, token_endpoint, jwks_uri. All required.
#   lti_registrations  lti_platform_id, client_id, public_key (text), private_key (text), kid.
#                      client_id is unique within one platform. The two key columns and kid are
#                      filled by the model, not by the caller.
#   lti_deployments    lti_registration_id, deployment_id. deployment_id is unique within one registration.
#
# Key generation: LtiRegistration makes a 2048 bit RSA key pair the first time it is saved, stores both
# halves as PEM text, and sets kid to a new random value. A later save never changes them.
# (Real apps encrypt the private key at rest, for example with `encrypts`. Skip that here and note it.)
#
# public_jwk: the public key as a JSON Web Key hash. json-jwt is already in the Gemfile.
# JSON::JWK.new(rsa_public_key, kid: kid, use: "sig", alg: "RS256") gives the right shape.
# The hash holds the public halves only: kty, n, e, kid, use, alg. Never d, p, q, dp, dq, or qi.
RSpec.describe "LTI 1.3 registration models" do
  describe LtiPlatform do
    it "is valid with the factory" do
      expect(build(:lti_platform)).to be_valid
    end

    %i[issuer name auth_endpoint token_endpoint jwks_uri].each do |field|
      it "needs #{field}" do
        expect(build(:lti_platform, field => nil)).not_to be_valid
      end
    end

    it "has one platform per issuer" do
      create(:lti_platform, issuer: "https://canvas.example.test")

      expect(build(:lti_platform, issuer: "https://canvas.example.test")).not_to be_valid
    end

    it "removes its registrations when it is destroyed" do
      platform = create(:lti_platform)
      create(:lti_registration, lti_platform: platform)

      expect { platform.destroy }.to change(LtiRegistration, :count).by(-1)
    end
  end

  describe LtiRegistration do
    it "is valid with the factory" do
      expect(build(:lti_registration)).to be_valid
    end

    it "needs a client_id" do
      expect(build(:lti_registration, client_id: nil)).not_to be_valid
    end

    it "has one registration per client_id on a platform" do
      platform = create(:lti_platform)
      create(:lti_registration, lti_platform: platform, client_id: "10000000000001")

      expect(build(:lti_registration, lti_platform: platform, client_id: "10000000000001")).not_to be_valid
    end

    it "lets two platforms use the same client_id" do
      create(:lti_registration, client_id: "10000000000001")

      expect(build(:lti_registration, client_id: "10000000000001")).to be_valid
    end

    describe "its key pair" do
      subject(:registration) { create(:lti_registration) }

      it "is made on the first save" do
        expect(registration.private_key).to start_with("-----BEGIN")
        expect(registration.public_key).to start_with("-----BEGIN")
        expect(registration.kid).to be_present
      end

      it "is a 2048 bit RSA pair that belongs together" do
        private_key = OpenSSL::PKey::RSA.new(registration.private_key)
        public_key = OpenSSL::PKey::RSA.new(registration.public_key)

        expect(private_key.n.num_bits).to eq(2048)
        expect(private_key).to be_private
        expect(public_key).not_to be_private
        expect(public_key.n).to eq(private_key.n)
      end

      it "does not change on a later save" do
        expect { registration.update!(client_id: "10000000000099") }
          .not_to change { registration.reload.attributes.slice("private_key", "public_key", "kid") }
      end

      it "is different for each registration" do
        other = create(:lti_registration)

        expect(other.private_key).not_to eq(registration.private_key)
        expect(other.kid).not_to eq(registration.kid)
      end
    end

    describe "#public_jwk" do
      subject(:jwk) { create(:lti_registration).then { |r| [ r, r.public_jwk ] } }

      let(:registration) { jwk.first }
      let(:hash) { jwk.last.stringify_keys }

      it "describes the public key" do
        expect(hash).to include("kty" => "RSA", "use" => "sig", "alg" => "RS256", "kid" => registration.kid)
        expect(hash["n"]).to be_present
        expect(hash["e"]).to be_present
      end

      it "never contains the private half" do
        expect(hash.keys & %w[d p q dp dq qi]).to be_empty
      end

      it "matches the stored public key" do
        public_key = OpenSSL::PKey::RSA.new(registration.public_key)
        n = OpenSSL::BN.new(Base64.urlsafe_decode64(hash["n"]), 2)

        expect(n).to eq(public_key.n)
      end
    end
  end

  describe LtiDeployment do
    it "is valid with the factory" do
      expect(build(:lti_deployment)).to be_valid
    end

    it "needs a deployment_id" do
      expect(build(:lti_deployment, deployment_id: nil)).not_to be_valid
    end

    it "has one deployment per deployment_id on a registration" do
      registration = create(:lti_registration)
      create(:lti_deployment, lti_registration: registration, deployment_id: "1:abc")

      expect(build(:lti_deployment, lti_registration: registration, deployment_id: "1:abc")).not_to be_valid
    end

    it "lets one registration have many deployments" do
      registration = create(:lti_registration)

      create(:lti_deployment, lti_registration: registration, deployment_id: "1:abc")

      expect(build(:lti_deployment, lti_registration: registration, deployment_id: "2:def")).to be_valid
    end
  end
end
