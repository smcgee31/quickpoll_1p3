require "rails_helper"

# Step E, part 2. After a 1.3 launch, the poll pages work, and the roles decide who may do what.
#
# What to build, in app/controllers/lti/launch_controller.rb, in launch_1p3:
#   after reset_session, store the answer next to the user and course ids:
#     session[:can_create_polls] = Lti1p3::Roles.new(verifier.claims).can_create_polls?
#   Store the yes or no answer only, not the raw roles. This is the same line as in launch_1p1.
#
# Nothing else changes. LaunchController, PollsController, and VotesController already work for any
# person and course in the session. These specs prove that a platform person and a platform course
# are enough. They run the whole 1.3 flow: launch, create a poll, launch as someone else, vote.
RSpec.describe "Polls after a 1.3 launch", type: :request do
  include_context "with 1.3 launches"

  let(:learner_roles) do
    [
      "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner",
      "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Student"
    ]
  end
  let(:teaching_assistant_roles) do
    [ "http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant" ]
  end
  let(:new_poll) { { poll: { question: "Favorite color?", options_text: "Red\nBlue" } } }

  def launch(claims = launch_claims, state: "state-1")
    post "/lti/launch", params: { id_token: sign_id_token(claims), state: state }
  end

  # Starts a second login (a second state) and launches as another person, in the same course.
  def launch_as(sub:, name:, roles:, state: "state-#{sub}")
    create(:lti_launch_state, lti_registration: registration, state: state, nonce: "nonce-#{sub}")
    launch(
      launch_claims("sub" => sub, "name" => name, "nonce" => "nonce-#{sub}", claim("roles") => roles),
      state: state
    )
  end

  describe "the session" do
    it "lets an instructor create polls" do
      launch

      expect(session[:can_create_polls]).to be(true)
    end

    it "lets a teaching assistant create polls" do
      launch(launch_claims(claim("roles") => teaching_assistant_roles))

      expect(session[:can_create_polls]).to be(true)
    end

    it "lets a learner vote only" do
      launch(launch_claims(claim("roles") => learner_roles))

      expect(session[:can_create_polls]).to be(false)
    end

    it "lets a launch with no roles claim vote only" do
      launch(launch_claims.except(claim("roles")))

      expect(session[:can_create_polls]).to be(false)
    end

    it "replaces the answer when a learner launches in the browser of an instructor" do
      launch
      launch_as(sub: "student-1", name: "Test Student 1", roles: learner_roles)

      expect(session[:can_create_polls]).to be(false)
    end
  end

  describe "the poll page" do
    it "shows the new poll form to an instructor" do
      launch
      get "/lti/polls"

      expect(response.body).to include("New poll", "poll[question]")
    end

    it "shows no form to a learner" do
      launch(launch_claims(claim("roles") => learner_roles))
      get "/lti/polls"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("New poll")
    end
  end

  describe "creating a poll" do
    it "lets an instructor create a poll in the course of the launch, as that person" do
      launch

      expect { post "/lti/polls", params: new_poll }.to change(Poll, :count).by(1)

      expect(Poll.last).to have_attributes(lti_context: LtiContext.last, creator: LtiUser.last, options: %w[Red Blue])
      expect(LtiContext.last.lti_platform).to eq(platform)
    end

    it "refuses a learner with 403" do
      launch(launch_claims(claim("roles") => learner_roles))

      expect { post "/lti/polls", params: new_poll }.not_to change(Poll, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "voting" do
    before do
      launch
      post "/lti/polls", params: new_poll
      launch_as(sub: "student-1", name: "Test Student 1", roles: learner_roles)
    end

    it "lets a learner of the course vote, and then shows the counts" do
      poll = Poll.last

      expect { post "/lti/polls/#{poll.id}/votes", params: { vote: { option_index: 1 } } }.to change(Vote, :count).by(1)

      expect(Vote.last.lti_user.lti1p3_sub).to eq("student-1")
      get "/lti/polls"
      expect(response.body).to include("Red: 0", "Blue: 1", "You voted: Blue")
    end

    it "refuses a second vote from the same learner" do
      poll = Poll.last
      post "/lti/polls/#{poll.id}/votes", params: { vote: { option_index: 0 } }

      expect { post "/lti/polls/#{poll.id}/votes", params: { vote: { option_index: 1 } } }.not_to change(Vote, :count)

      expect(flash[:alert]).to eq("You already voted on this poll.")
    end

    it "shows a learner no counts until the learner has voted" do
      get "/lti/polls"

      expect(response.body).to include("Favorite color?", "vote[option_index]")
      expect(response.body).not_to match(/Red: \d/)
    end

    it "does not show the poll to a learner of another course" do
      other_course = launch_claims(
        "sub" => "student-1", "nonce" => "nonce-other", claim("roles") => learner_roles,
        claim("context") => { "id" => "context-other", "title" => "Other Course" }
      )
      create(:lti_launch_state, lti_registration: registration, state: "state-other", nonce: "nonce-other")
      launch(other_course, state: "state-other")

      get "/lti/polls"

      expect(response.body).not_to include("Favorite color?")
    end
  end
end
