require "rails_helper"

# Step B of the 1.3 build: two JSON pages Canvas reads. Neither one needs a launch or a session.
#
# 1. GET /lti/jwks (Lti::JwksController#show, route name lti_jwks)
#    The JWKS endpoint. "JWKS" means JSON Web Key Set: a list of PUBLIC keys. Canvas fetches this
#    list to check anything our tool signs. The `kid` on each key tells Canvas which one to use.
#    Answer: {"keys": [ ...the public_jwk of every LtiRegistration... ]}.
#    This is the 1.3 answer to "how does Canvas trust us?" In 1.1 Canvas trusted a shared secret.
#
# 2. GET /lti/tool_config (Lti::ToolConfigController#show, route name lti_tool_config)
#    The JSON you paste into a Canvas developer key. It replaces the 1.1 XML at /lti/config.
#    It tells Canvas where our endpoints are. Every URL starts with Rails.configuration.x.public_base_url,
#    the same setting the 1.1 verifier used. Build the URLs from it, not from request.host.
#
#    {
#      "title": "QuickPoll 1.3",
#      "description": <any non-empty text>,
#      "oidc_initiation_url": "<base>/lti/login",     where Canvas starts a launch (step C)
#      "target_link_uri": "<base>/lti/launch",         where the launch lands (step D)
#      "redirect_uris": ["<base>/lti/launch"],         the only URLs Canvas may redirect the id_token to
#      "public_jwk_url": "<base>/lti/jwks",            the page from item 1
#      "scopes": [],                                   no grade passback yet
#      "extensions": [{
#        "platform": "canvas.instructure.com",
#        "privacy_level": "public",                    Canvas sends names and ids
#        "settings": { "placements": [{
#          "placement": "course_navigation",
#          "message_type": "LtiResourceLinkRequest",
#          "text": "QuickPoll 1.3",
#          "target_link_uri": "<base>/lti/launch"
#        }]}
#      }]
#    }
#
# The Canvas-specific parts (extensions, placements) are my best knowledge of the format. Step G
# checks them against what Canvas accepts. Change this spec and the controller together if Canvas disagrees.
RSpec.describe "Tool JSON pages", type: :request do
  let(:public_base_url) { "http://quickpoll-test.example" }

  around do |example|
    original = Rails.configuration.x.public_base_url
    Rails.configuration.x.public_base_url = public_base_url
    example.run
  ensure
    Rails.configuration.x.public_base_url = original
  end

  describe "GET /lti/jwks" do
    it "answers 200 with JSON" do
      get "/lti/jwks"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
    end

    it "answers an empty list when nothing is registered" do
      get "/lti/jwks"

      expect(response.parsed_body).to eq({ "keys" => [] })
    end

    it "lists the public key of every registration" do
      first = create(:lti_registration)
      second = create(:lti_registration)

      get "/lti/jwks"

      keys = response.parsed_body["keys"]
      expect(keys.map { |key| key["kid"] }).to contain_exactly(first.kid, second.kid)
      expect(keys).to all(include("kty" => "RSA", "alg" => "RS256", "use" => "sig"))
    end

    it "never lists a private value" do
      create(:lti_registration)

      get "/lti/jwks"

      expect(response.body).not_to match(/"(d|p|q|dp|dq|qi)"\s*:/)
      expect(response.body).not_to include("PRIVATE KEY")
    end

    it "needs no session" do
      get "/lti/jwks"

      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  describe "GET /lti/tool_config" do
    subject(:config) { response.parsed_body }

    before { get "/lti/tool_config" }

    it "answers 200 with JSON" do
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
    end

    it "names the tool" do
      expect(config["title"]).to eq("QuickPoll 1.3")
      expect(config["description"]).to be_present
    end

    it "points Canvas at our endpoints, built from the public base URL" do
      expect(config).to include(
        "oidc_initiation_url" => "http://quickpoll-test.example/lti/login",
        "target_link_uri" => "http://quickpoll-test.example/lti/launch",
        "redirect_uris" => [ "http://quickpoll-test.example/lti/launch" ],
        "public_jwk_url" => "http://quickpoll-test.example/lti/jwks"
      )
    end

    it "asks for no scopes" do
      expect(config["scopes"]).to eq([])
    end

    it "puts the tool in course navigation" do
      extension = config["extensions"].first

      expect(extension).to include("platform" => "canvas.instructure.com", "privacy_level" => "public")
      expect(extension["settings"]["placements"]).to contain_exactly(
        include(
          "placement" => "course_navigation",
          "message_type" => "LtiResourceLinkRequest",
          "text" => "QuickPoll 1.3",
          "target_link_uri" => "http://quickpoll-test.example/lti/launch"
        )
      )
    end
  end
end
