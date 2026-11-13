require "rails_helper"

# Step C of the 1.3 build, part 1: remember a login we started.
#
# A 1.3 launch is two trips, not one:
#   1. Canvas sends the browser to our login URL.  We answer with a redirect back to Canvas.
#   2. Canvas sends the browser to our launch URL, with a signed id_token.
# Trip 2 must prove it answers trip 1, or an attacker could feed us a launch we never asked for.
# So trip 1 invents two random strings and keeps them:
#   state  goes to Canvas and comes back unchanged. It says "this answers a login I started".
#   nonce  goes to Canvas, and Canvas puts it INSIDE the signed id_token. It says "this token is fresh".
# This table is where we keep them between the two trips. (Step D reads them back and checks them.)
# 1.1 had the same idea: used_nonces. The 1.3 table also keeps state, and it keeps the values
# BEFORE the launch, not after.
#
# What to build (rails g model LtiLaunchState ..., then edit the migration):
#   lti_launch_states   lti_registration_id (FK, required), state (required, unique), nonce (required),
#                       used_at (datetime, nullable). Timestamps.
#   LtiLaunchState      belongs_to :lti_registration. Validate state and nonce present, state unique.
RSpec.describe LtiLaunchState do
  it "is valid with the factory" do
    expect(build(:lti_launch_state)).to be_valid
  end

  it "needs a state" do
    expect(build(:lti_launch_state, state: nil)).not_to be_valid
  end

  it "needs a nonce" do
    expect(build(:lti_launch_state, nonce: nil)).not_to be_valid
  end

  it "needs a registration" do
    expect(build(:lti_launch_state, lti_registration: nil)).not_to be_valid
  end

  it "has one row per state" do
    create(:lti_launch_state, state: "abc")

    expect(build(:lti_launch_state, state: "abc")).not_to be_valid
  end

  it "starts out unused" do
    expect(create(:lti_launch_state).used_at).to be_nil
  end

  it "is removed with its registration" do
    registration = create(:lti_registration)
    create(:lti_launch_state, lti_registration: registration)

    expect { registration.destroy }.to change(described_class, :count).by(-1)
  end
end
