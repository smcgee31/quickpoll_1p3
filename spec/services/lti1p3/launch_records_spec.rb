require "rails_helper"

# Step D3, part 1. Turn a verified 1.3 launch into two rows: the person and the course.
#
# This is the 1.3 twin of Lti1p1::LaunchRecords. Call it only after Lti1p3::LaunchVerifier#call
# returned true. It trusts the claims.
#
# What to build: app/services/lti1p3/launch_records.rb
#   records = Lti1p3::LaunchRecords.new(platform: platform, claims: verifier.claims)
#   records.call      # true. It saves both rows in one transaction.
#   records.user      # the LtiUser
#   records.context   # the LtiContext
#
#   - The person: find or create the LtiUser of this platform with lti1p3_sub equal to claims["sub"].
#     Save the "name" claim in name. A launch with no name, or a blank one, keeps the name we have.
#   - The course: find or create the LtiContext of this platform with context_id equal to the "id" in
#     the context claim ("https://purl.imsglobal.org/spec/lti/claim/context"). Save its "title" and
#     "label". A missing or blank title or label keeps what we have.
#   - Look rows up through the platform: platform.lti_users and platform.lti_contexts. The same sub on
#     another platform is another person.
#   - The rows have no consumer and no lti1p1_user_id. Those are 1.1 things.
RSpec.describe "Lti1p3::LaunchRecords" do
  let(:platform) { create(:lti_platform) }
  let(:context_claim) { "https://purl.imsglobal.org/spec/lti/claim/context" }
  let(:claims) do
    {
      "sub" => "lti-user-1",
      "name" => "Test Teacher 1",
      context_claim => { "id" => "context-abc", "label" => "TC1", "title" => "Test Course 1" }
    }
  end

  def records_for(claims, platform: self.platform)
    Lti1p3::LaunchRecords.new(platform: platform, claims: claims)
  end

  it "creates the person on the platform" do
    records = records_for(claims)

    expect(records.call).to be(true)

    expect(records.user).to have_attributes(
      lti_platform: platform, lti1p3_sub: "lti-user-1", name: "Test Teacher 1", lti_consumer: nil, lti1p1_user_id: nil
    )
    expect(records.user).to be_persisted
  end

  it "creates the course on the platform" do
    records = records_for(claims)
    records.call

    expect(records.context).to have_attributes(
      lti_platform: platform, context_id: "context-abc", title: "Test Course 1", label: "TC1", lti_consumer: nil
    )
    expect(records.context).to be_persisted
  end

  it "finds the same person and course the second time" do
    first = records_for(claims)
    first.call

    expect { records_for(claims).call }.not_to change { [ LtiUser.count, LtiContext.count ] }
    expect(records_for(claims).tap(&:call).user).to eq(first.user)
  end

  it "updates the name and the course title when they change" do
    records_for(claims).call
    changed = claims.merge("name" => "New Name", context_claim => { "id" => "context-abc", "title" => "New Title", "label" => "NT" })

    records = records_for(changed)
    records.call

    expect(records.user.reload.name).to eq("New Name")
    expect(records.context.reload).to have_attributes(title: "New Title", label: "NT")
  end

  it "keeps the name and the course title when a launch leaves them out" do
    records_for(claims).call
    sparse = { "sub" => "lti-user-1", "name" => "", context_claim => { "id" => "context-abc" } }

    records = records_for(sparse)
    records.call

    expect(records.user.reload.name).to eq("Test Teacher 1")
    expect(records.context.reload).to have_attributes(title: "Test Course 1", label: "TC1")
  end

  it "saves a person with no name when no launch ever sent one" do
    records = records_for(claims.except("name"))

    expect(records.call).to be(true)
    expect(records.user.name).to be_nil
  end

  it "makes a new course for a new context id, and keeps the same person" do
    first = records_for(claims)
    first.call
    second = records_for(claims.merge(context_claim => { "id" => "context-xyz", "title" => "Other Course" }))

    expect { second.call }.to change(LtiContext, :count).by(1)
    expect(LtiUser.count).to eq(1)
    expect(second.user).to eq(first.user)
    expect(second.context).not_to eq(first.context)
  end

  it "treats the same sub on another platform as another person and the same context id as another course" do
    first = records_for(claims)
    first.call
    other = records_for(claims, platform: create(:lti_platform))

    expect { other.call }.to change(LtiUser, :count).by(1).and change(LtiContext, :count).by(1)
    expect(other.user).not_to eq(first.user)
    expect(other.context).not_to eq(first.context)
  end
end
