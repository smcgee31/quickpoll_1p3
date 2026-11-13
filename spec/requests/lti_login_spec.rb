require "rails_helper"

# Step C of the 1.3 build, part 2: the OIDC login. Trip 1 of a 1.3 launch.
#
# OIDC is OpenID Connect. Canvas calls our "oidc_initiation_url" (/lti/login) and says "someone wants
# to launch you". We do not trust that yet. We answer with a redirect to Canvas's own login endpoint
# (platform.auth_endpoint) and say "ask Canvas to prove it, and send the proof to /lti/launch".
#
# Canvas sends these (a POST form, or a GET, both must work):
#   iss               who is asking. Matches LtiPlatform#issuer. Example: https://canvas.instructure.com
#   client_id         which developer key. Matches LtiRegistration#client_id.
#   login_hint        an opaque value for Canvas. We pass it back unchanged.
#   lti_message_hint  another opaque value for Canvas. Pass it back unchanged, when it was sent.
#   target_link_uri   the launch URL Canvas will use. Not used in this step.
#   lti_deployment_id which install. Checked in step D, not here.
#
# What to build:
#   - Route: `match "login", to: "login#create", via: %i[get post], as: :login` in namespace :lti.
#   - Lti::LoginController (singular: one job, no table behind it) < BaseController. BaseController
#     already skips CSRF for us, which Canvas needs, and allows the iframe.
#   - Find the platform by iss, then the registration by client_id ON THAT platform. Any miss,
#     or a missing login_hint, answers 400 and saves nothing. Never say which one was missing.
#   - Make a state and a nonce. Each is SecureRandom.hex(16) or longer (32 characters or more), new for
#     every login. Save them as an LtiLaunchState for that registration.
#   - Redirect (302) to platform.auth_endpoint with these query params:
#       scope=openid  response_type=id_token  response_mode=form_post  prompt=none
#       client_id  redirect_uri=<public base url>/lti/launch  login_hint  state  nonce
#       lti_message_hint  (only when Canvas sent one)
#     Build redirect_uri from Rails.configuration.x.public_base_url, never from request.host.
#
# No cookie holds the state. The database does. A cookie would be dropped by browsers that block
# third-party cookies inside an iframe, which is the problem 1.3 Canvas solves with lti_storage_target.
# The cost: nothing ties this state to this browser. Note it in TODO.md and move on.
RSpec.describe "OIDC login", type: :request do
  let(:public_base_url) { "http://quickpoll-test.example" }
  let(:platform) do
    create(:lti_platform,
           issuer: "https://canvas.example.test",
           auth_endpoint: "https://canvas.example.test/api/lti/authorize_redirect")
  end
  let!(:registration) { create(:lti_registration, lti_platform: platform, client_id: "10000000000001") }
  let(:login_params) do
    {
      "iss" => "https://canvas.example.test",
      "client_id" => "10000000000001",
      "login_hint" => "login-hint-value",
      "lti_message_hint" => "message-hint-value",
      "target_link_uri" => "http://quickpoll-test.example/lti/launch",
      "lti_deployment_id" => "1:abc"
    }
  end
  let(:location) { URI.parse(response.location) }
  let(:query) { Rack::Utils.parse_query(location.query) }

  around do |example|
    original = Rails.configuration.x.public_base_url
    Rails.configuration.x.public_base_url = public_base_url
    example.run
  ensure
    Rails.configuration.x.public_base_url = original
  end

  context "with a known platform and registration" do
    before { post "/lti/login", params: login_params }

    it "redirects to the auth endpoint of the platform" do
      expect(response).to have_http_status(:found)
      expect("#{location.scheme}://#{location.host}#{location.path}")
        .to eq("https://canvas.example.test/api/lti/authorize_redirect")
    end

    it "asks Canvas for an id_token, posted back to our launch URL" do
      expect(query).to include(
        "scope" => "openid",
        "response_type" => "id_token",
        "response_mode" => "form_post",
        "prompt" => "none",
        "client_id" => "10000000000001",
        "redirect_uri" => "http://quickpoll-test.example/lti/launch"
      )
    end

    it "passes the hints back unchanged" do
      expect(query).to include("login_hint" => "login-hint-value", "lti_message_hint" => "message-hint-value")
    end

    it "sends a long random state and nonce" do
      expect(query["state"].length).to be >= 32
      expect(query["nonce"].length).to be >= 32
      expect(query["state"]).not_to eq(query["nonce"])
    end

    it "saves the state and nonce for the launch to check" do
      saved = LtiLaunchState.find_by!(state: query["state"])

      expect(saved.nonce).to eq(query["nonce"])
      expect(saved.lti_registration).to eq(registration)
      expect(saved.used_at).to be_nil
    end

    it "allows the response to render in a Canvas iframe" do
      expect(response.headers["X-Frame-Options"]).to be_nil
    end
  end

  it "makes a new state and nonce for every login" do
    post "/lti/login", params: login_params
    first = Rack::Utils.parse_query(URI.parse(response.location).query)
    post "/lti/login", params: login_params
    second = Rack::Utils.parse_query(URI.parse(response.location).query)

    expect(second["state"]).not_to eq(first["state"])
    expect(second["nonce"]).not_to eq(first["nonce"])
    expect(LtiLaunchState.count).to eq(2)
  end

  it "answers a GET the same way" do
    get "/lti/login", params: login_params

    expect(response).to have_http_status(:found)
    expect(LtiLaunchState.count).to eq(1)
  end

  it "leaves out lti_message_hint when Canvas did not send one" do
    post "/lti/login", params: login_params.except("lti_message_hint")

    expect(query).not_to have_key("lti_message_hint")
  end

  describe "a login it cannot trust" do
    def expect_refused
      expect { yield }.not_to change(LtiLaunchState, :count)
      expect(response).to have_http_status(:bad_request)
      expect(response.body).not_to include("canvas.example.test")
    end

    it "refuses an unknown issuer" do
      expect_refused { post "/lti/login", params: login_params.merge("iss" => "https://evil.example.test") }
    end

    it "refuses an unknown client_id" do
      expect_refused { post "/lti/login", params: login_params.merge("client_id" => "99999999999999") }
    end

    it "refuses a client_id that belongs to another platform" do
      other = create(:lti_registration, client_id: "20000000000002")

      expect_refused { post "/lti/login", params: login_params.merge("client_id" => other.client_id) }
    end

    it "refuses a missing client_id" do
      expect_refused { post "/lti/login", params: login_params.except("client_id") }
    end

    it "refuses a missing login_hint" do
      expect_refused { post "/lti/login", params: login_params.except("login_hint") }
    end

    it "refuses a missing issuer" do
      expect_refused { post "/lti/login", params: login_params.except("iss") }
    end
  end
end
