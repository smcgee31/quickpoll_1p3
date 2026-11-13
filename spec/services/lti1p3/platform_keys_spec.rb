require "rails_helper"

# Step D2, part 1. Get the public keys of a platform.
#
# Canvas signs the id_token. To check the signature we need the public key of Canvas. Canvas
# publishes its keys at a URL, the jwks_uri of the platform. This class downloads them.
#
# What to build: app/services/lti1p3/platform_keys.rb
#   - Lti1p3::PlatformKeys.fetch(platform) is a CLASS method. It returns the "keys" array from the JSON
#     at platform.jwks_uri: an array of hashes, one per key. Do not turn them into objects here.
#   - Download with `Net::HTTP.get_response(URI(platform.jwks_uri))`. The spec stubs exactly that call.
#   - Raise Lti1p3::PlatformKeys::Unavailable (a StandardError) for every way this can go wrong:
#       * the answer is not a success (Net::HTTPSuccess)
#       * the body is not JSON
#       * the JSON has no "keys" array
#       * the request itself fails: SocketError, Timeout::Error, SystemCallError (connection refused)
#
# No cache for now. Every launch downloads the keys. Canvas rotates its keys, and a stale cache is a
# classic 1.3 bug. TODO.md will note the cost.
RSpec.describe "Lti1p3::PlatformKeys" do
  let(:platform) { create(:lti_platform, jwks_uri: "https://canvas.example.test/api/lti/security/jwks") }
  let(:keys) { [ { "kty" => "RSA", "kid" => "k1", "n" => "abc", "e" => "AQAB" } ] }

  def answer(klass, code, body)
    klass.new("1.1", code, "x").tap do |response|
      allow(response).to receive(:body).and_return(body)
    end
  end

  def stub_download(response)
    allow(Net::HTTP).to receive(:get_response).with(URI(platform.jwks_uri)).and_return(response)
  end

  it "returns the keys from the JWKS of the platform" do
    stub_download(answer(Net::HTTPOK, "200", { "keys" => keys }.to_json))

    expect(Lti1p3::PlatformKeys.fetch(platform)).to eq(keys)
  end

  it "raises Unavailable when the platform answers with an error" do
    stub_download(answer(Net::HTTPInternalServerError, "500", "oops"))

    expect { Lti1p3::PlatformKeys.fetch(platform) }.to raise_error(Lti1p3::PlatformKeys::Unavailable)
  end

  it "raises Unavailable when the body is not JSON" do
    stub_download(answer(Net::HTTPOK, "200", "<html>login</html>"))

    expect { Lti1p3::PlatformKeys.fetch(platform) }.to raise_error(Lti1p3::PlatformKeys::Unavailable)
  end

  it "raises Unavailable when the JSON has no keys" do
    stub_download(answer(Net::HTTPOK, "200", { "other" => [] }.to_json))

    expect { Lti1p3::PlatformKeys.fetch(platform) }.to raise_error(Lti1p3::PlatformKeys::Unavailable)
  end

  [ SocketError, Net::OpenTimeout, Errno::ECONNREFUSED ].each do |error|
    it "raises Unavailable when the request fails with #{error}" do
      allow(Net::HTTP).to receive(:get_response).and_raise(error)

      expect { Lti1p3::PlatformKeys.fetch(platform) }.to raise_error(Lti1p3::PlatformKeys::Unavailable)
    end
  end
end
