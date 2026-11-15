require "rails_helper"

# Step E, part 1. Read the roles of a 1.3 launch.
#
# In 1.1 the roles came as comma-separated text in two fields, and the name sat after the last "/".
# In 1.3 the claim "https://purl.imsglobal.org/spec/lti/claim/roles" is an ARRAY of URIs. The name
# sits after the "#":
#
#   http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor                 course role
#   http://purl.imsglobal.org/vocab/lis/v2/membership#Learner                    course role
#   http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant   sub-role of Instructor
#   http://purl.imsglobal.org/vocab/lis/v2/institution/person#Administrator      institution role
#   http://purl.imsglobal.org/vocab/lis/v2/system/person#SysAdmin                system role
#
# The 1.1 rule "text after the last /" gives "membership#Instructor" for the first URI. That is wrong.
# The rule for 1.3: when the URI has a "#", the name is the text after the LAST "#". Otherwise the name is
# the text after the last "/". (The standard also allows a bare short name like "Instructor" for course
# roles. It has no "#" and no "/", so the second rule returns it whole.)
#
# What to build: app/services/lti1p3/roles.rb. The same interface as Lti1p1::Roles:
#   Lti1p3::Roles.new(claims)     # claims is the Hash from Lti1p3::LaunchVerifier#claims
#     #names                -> Array of names, no duplicates, in the order they arrive
#     #instructor?  #learner?  #administrator?  #teaching_assistant?
#     #can_create_polls?    -> true for an instructor or a teaching assistant
#   Compare whole names. Ignore blank entries and spaces. A missing claim means no roles.
#
# A caution. The shapes below come from the IMS standard and my reading of Canvas, not from a real
# Canvas launch. Step G logs the real claim. Check it, and change this spec if Canvas differs.
RSpec.describe "Lti1p3::Roles" do
  let(:roles_claim) { "https://purl.imsglobal.org/spec/lti/claim/roles" }
  let(:instructor) { "http://purl.imsglobal.org/vocab/lis/v2/membership#Instructor" }
  let(:learner) { "http://purl.imsglobal.org/vocab/lis/v2/membership#Learner" }
  let(:teaching_assistant) { "http://purl.imsglobal.org/vocab/lis/v2/membership/Instructor#TeachingAssistant" }
  let(:institution_instructor) { "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Instructor" }
  let(:institution_student) { "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Student" }
  let(:administrator) { "http://purl.imsglobal.org/vocab/lis/v2/institution/person#Administrator" }
  let(:sysadmin) { "http://purl.imsglobal.org/vocab/lis/v2/system/person#SysAdmin" }

  def roles_for(*uris)
    Lti1p3::Roles.new({ roles_claim => uris.flatten })
  end

  describe "#names" do
    it "takes the name after the # of a course role" do
      expect(roles_for(instructor, learner).names).to eq(%w[Instructor Learner])
    end

    it "takes only the sub-role name from a sub-role URI" do
      expect(roles_for(teaching_assistant).names).to eq([ "TeachingAssistant" ])
    end

    it "takes the name after the last / when the URI has no #" do
      expect(roles_for("http://purl.imsglobal.org/vocab/lis/v2/membership/Mentor").names).to eq([ "Mentor" ])
    end

    it "accepts a bare short name" do
      expect(roles_for("Instructor").names).to eq([ "Instructor" ])
    end

    it "counts the same name once, from a course role and an institution role" do
      expect(roles_for(instructor, institution_instructor, learner).names).to eq(%w[Instructor Learner])
    end

    it "trims spaces and ignores blank entries and entries with an empty name" do
      expect(roles_for(" #{instructor} ", "", nil, "http://purl.imsglobal.org/vocab/lis/v2/membership#").names)
        .to eq([ "Instructor" ])
    end

    it "has no names when the claim is missing" do
      expect(Lti1p3::Roles.new({}).names).to eq([])
    end

    it "has no names when the claim is not an Array of Strings" do
      expect(Lti1p3::Roles.new({ roles_claim => nil }).names).to eq([])
      expect(Lti1p3::Roles.new({ roles_claim => [] }).names).to eq([])
    end
  end

  describe "the questions" do
    it "knows an instructor" do
      roles = roles_for(instructor, institution_instructor)

      expect(roles).to be_instructor
      expect(roles).not_to be_learner
      expect(roles).not_to be_teaching_assistant
    end

    it "knows a learner" do
      roles = roles_for(learner, institution_student)

      expect(roles).to be_learner
      expect(roles).not_to be_instructor
    end

    it "knows a teaching assistant, who is not an instructor by that role alone" do
      roles = roles_for(teaching_assistant)

      expect(roles).to be_teaching_assistant
      expect(roles).not_to be_instructor
    end

    it "knows an administrator" do
      expect(roles_for(administrator, sysadmin)).to be_administrator
    end

    it "does not match part of a longer name" do
      roles = roles_for("http://purl.imsglobal.org/vocab/lis/v2/membership#InstructorAssistant")

      expect(roles).not_to be_instructor
      expect(roles.names).to eq([ "InstructorAssistant" ])
    end
  end

  describe "#can_create_polls?" do
    it "is true for an instructor" do
      expect(roles_for(instructor)).to be_can_create_polls
    end

    it "is true for a teaching assistant" do
      expect(roles_for(teaching_assistant)).to be_can_create_polls
    end

    it "is true for an instructor at the institution level only" do
      expect(roles_for(institution_instructor)).to be_can_create_polls
    end

    it "is false for a learner" do
      expect(roles_for(learner, institution_student)).not_to be_can_create_polls
    end

    it "is false for an administrator with no teaching role" do
      expect(roles_for(administrator, sysadmin)).not_to be_can_create_polls
    end

    it "is false when there are no roles" do
      expect(Lti1p3::Roles.new({})).not_to be_can_create_polls
    end
  end
end
