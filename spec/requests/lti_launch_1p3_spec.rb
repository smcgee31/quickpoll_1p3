require "rails_helper"

# Step D3, part 2. POST /lti/launch accepts a 1.3 launch.
#
# Canvas form-posts two fields to /lti/launch: id_token and state. When id_token is present this is a
# 1.3 launch. When it is not, the old 1.1 code still handles the request. Both live in the same
# controller until step F removes the 1.1 side.
#
# What to build in app/controllers/lti/launch_controller.rb:
#   - Skip the 1.1 before_action for a 1.3 launch: `before_action :verify_launch, unless: :lti1p3_launch?`
#     with a private `lti1p3_launch?` that is true when params[:id_token] is present.
#   - In `create`, branch on lti1p3_launch?. Move the existing 1.1 code into its own private method and
#     put the 1.3 code in another. Each method ends with the redirect or the render.
#   - The 1.3 method:
#       1. verifier = Lti1p3::LaunchVerifier.new(id_token: params[:id_token], state: params[:state])
#       2. If verifier.call is false: `reject(verifier.error)`. That is the existing method. It logs
#          "[lti launch] rejected: <reason>" and answers 401 "Launch rejected." The page never says
#          WHY. The log does.
#       3. Otherwise: records = Lti1p3::LaunchRecords.new(platform: verifier.registration.lti_platform,
#          claims: verifier.claims) and records.call.
#       4. reset_session, then store session[:lti_user_id] and session[:lti_context_id].
#       5. redirect_to lti_polls_path, status: :see_other
#     Do NOT store can_create_polls yet. Roles are step E. Until then nobody can create polls after a
#     1.3 launch.
#
# These specs use the "with 1.3 launches" context in spec/support/lti1p3_launches.rb.
RSpec.describe "POST /lti/launch with an id_token", type: :request do
  include_context "with 1.3 launches"

  def launch(token = sign_id_token, state: "state-1")
    post "/lti/launch", params: { id_token: token, state: state }
  end

  def second_state(nonce: "nonce-2")
    create(:lti_launch_state, lti_registration: registration, state: "state-2", nonce: nonce)
  end

  context "with a launch Canvas signed correctly" do
    it "redirects to the poll page with 303" do
      launch

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to("/lti/polls")
    end

    it "creates the person and the course on the platform" do
      expect { launch }.to change(LtiUser, :count).by(1).and change(LtiContext, :count).by(1)

      expect(LtiUser.last).to have_attributes(lti_platform: platform, lti1p3_sub: "lti-user-1", name: "Test Teacher 1")
      expect(LtiContext.last).to have_attributes(lti_platform: platform, context_id: "context-abc", title: "Test Course 1")
    end

    it "starts the session for that person and course" do
      launch

      expect(session[:lti_user_id]).to eq(LtiUser.last.id)
      expect(session[:lti_context_id]).to eq(LtiContext.last.id)
    end

    it "uses up the state" do
      launch

      expect(launch_state.reload.used_at).not_to be_nil
    end

    it "shows the poll page with the name of the person and the course" do
      launch
      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Test Teacher 1", "Test Course 1")
    end

    it "allows the response to render in a Canvas iframe" do
      launch

      expect(response.headers["X-Frame-Options"]).to be_nil
    end

    it "does not need an authenticity token, because Canvas cannot send one" do
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true

      launch

      expect(response).to have_http_status(:see_other)
    ensure
      ActionController::Base.allow_forgery_protection = original
    end
  end

  context "when the same person launches again" do
    it "makes no second person or course, and starts the session again" do
      launch
      second_state
      first_session = session[:lti_user_id]

      expect { launch(sign_id_token(launch_claims("nonce" => "nonce-2")), state: "state-2") }
        .not_to change { [ LtiUser.count, LtiContext.count ] }

      expect(session[:lti_user_id]).to eq(first_session)
    end

    it "replaces the course in the session when the launch is from another course" do
      launch
      second_state
      other_course = launch_claims("nonce" => "nonce-2", claim("context") => { "id" => "context-xyz", "title" => "Other" })

      launch(sign_id_token(other_course), state: "state-2")

      expect(session[:lti_context_id]).to eq(LtiContext.find_by(context_id: "context-xyz").id)
      expect(LtiUser.count).to eq(1)
    end
  end

  context "with a launch it cannot trust" do
    it "refuses the same launch the second time (a replay)" do
      launch
      expect(response).to have_http_status(:see_other)

      expect { launch }.not_to change { [ LtiUser.count, LtiContext.count ] }

      expect(response).to have_http_status(:unauthorized)
    end

    {
      "a token signed with another key" => :bad_signature,
      "a token with the wrong nonce" => :wrong_nonce,
      "an expired token" => :expired
    }.each do |label, reason|
      it "answers 401 and saves nothing for #{label}" do
        token = case reason
        when :bad_signature then sign_id_token(key: OpenSSL::PKey::RSA.generate(2048))
        when :wrong_nonce then sign_id_token(launch_claims("nonce" => "nope"))
        when :expired then sign_id_token(launch_claims("exp" => now.to_i - 1))
        end

        expect { launch(token) }.not_to change { [ LtiUser.count, LtiContext.count ] }

        expect(response).to have_http_status(:unauthorized)
        expect(response.body).to eq("Launch rejected.")
        expect(session[:lti_user_id]).to be_nil
        expect(launch_state.reload.used_at).to be_nil
      end
    end

    it "answers 401 for a state we never made" do
      launch(state: "never-made")

      expect(response).to have_http_status(:unauthorized)
    end

    it "logs the reason, and keeps it off the page" do
      allow(Rails.logger).to receive(:warn)

      launch(sign_id_token(launch_claims("nonce" => "nope")))

      expect(Rails.logger).to have_received(:warn).with("[lti launch] rejected: wrong_nonce")
      expect(response.body).not_to include("nonce")
    end

    it "does not log the token" do
      logged = []
      allow(Rails.logger).to receive(:warn) { |message| logged << message }
      token = sign_id_token(launch_claims("nonce" => "nope"))

      launch(token)

      expect(logged.join).not_to include(token)
    end

    it "answers 401 for a launch with neither an id_token nor a 1.1 signature" do
      post "/lti/launch", params: { state: "state-1" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
