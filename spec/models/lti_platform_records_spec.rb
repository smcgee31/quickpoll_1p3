require "rails_helper"

# Step D1 of the 1.3 build: people and courses can belong to a platform.
#
# In 1.1 every LtiUser and LtiContext belongs to an LtiConsumer (one key and secret). In 1.3 there is
# no consumer. A person is "sub" on a platform, and a course is a context id on a platform. This step
# adds the platform side and keeps the consumer side working. Both exist for a while. Step F removes
# the consumer side.
#
# What to build:
#   - A migration. Use `rails g migration AddLtiPlatformToLtiUsersAndLtiContexts`, then fill in `change`:
#       * add_reference to lti_users and to lti_contexts: :lti_platform, foreign_key: true. It must be
#         nullable, because every row that exists today has a consumer and no platform.
#       * change_column_null to true for lti_users.lti_consumer_id, lti_contexts.lti_consumer_id, and
#         lti_users.lti1p1_user_id. A person from a 1.3 launch has no consumer and no 1.1 user id.
#       * a unique index on lti_users [:lti_platform_id, :lti1p3_sub], with `where: "lti1p3_sub IS NOT NULL"`.
#       * a unique index on lti_contexts [:lti_platform_id, :context_id].
#   - LtiUser and LtiContext: `belongs_to :lti_consumer, optional: true` and
#     `belongs_to :lti_platform, optional: true`.
#   - A row must have an owner: a consumer or a platform. When it has neither, add this error to :base:
#       "must belong to a consumer or a platform"
#   - LtiUser: lti1p1_user_id is required only when the user has a consumer. lti1p3_sub is required
#     only when the user has a platform. The existing uniqueness rules stay.
#   - LtiPlatform: has_many :lti_users and has_many :lti_contexts, both dependent: :destroy.
#
# The `:lti1p3` trait in spec/factories/lti1p3.rb builds a row that belongs to a platform.
RSpec.describe "Users and courses of a platform" do
  let(:platform) { create(:lti_platform) }

  describe LtiUser do
    it "is valid with a platform and a sub, and no consumer" do
      user = build(:lti_user, :lti1p3, lti_platform: platform)

      expect(user).to be_valid
      expect(user.lti_consumer).to be_nil
      expect(user.lti1p1_user_id).to be_nil
    end

    it "is not valid with no consumer and no platform" do
      user = build(:lti_user, :lti1p3, lti_platform: nil)

      expect(user).not_to be_valid
      expect(user.errors[:base]).to include("must belong to a consumer or a platform")
    end

    it "needs a sub when it has a platform" do
      user = build(:lti_user, :lti1p3, lti_platform: platform, lti1p3_sub: nil)

      expect(user).not_to be_valid
      expect(user.errors.attribute_names).to include(:lti1p3_sub)
    end

    it "still needs an lti1p1_user_id when it has a consumer" do
      user = build(:lti_user, lti1p1_user_id: nil)

      expect(user).not_to be_valid
      expect(user.errors.attribute_names).to include(:lti1p1_user_id)
    end

    it "rejects the same sub twice on one platform" do
      create(:lti_user, :lti1p3, lti_platform: platform, lti1p3_sub: "same")

      expect(build(:lti_user, :lti1p3, lti_platform: platform, lti1p3_sub: "same")).not_to be_valid
    end

    it "allows the same sub on two platforms" do
      create(:lti_user, :lti1p3, lti_platform: platform, lti1p3_sub: "same")

      expect(build(:lti_user, :lti1p3, lti_platform: create(:lti_platform), lti1p3_sub: "same")).to be_valid
    end

    it "has a database index that rejects the same sub twice on one platform" do
      create(:lti_user, :lti1p3, lti_platform: platform, lti1p3_sub: "same")
      duplicate = build(:lti_user, :lti1p3, lti_platform: platform, lti1p3_sub: "same")

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe LtiContext do
    it "is valid with a platform and no consumer" do
      context = build(:lti_context, :lti1p3, lti_platform: platform)

      expect(context).to be_valid
      expect(context.lti_consumer).to be_nil
    end

    it "is not valid with no consumer and no platform" do
      context = build(:lti_context, :lti1p3, lti_platform: nil)

      expect(context).not_to be_valid
      expect(context.errors[:base]).to include("must belong to a consumer or a platform")
    end

    it "rejects the same context_id twice on one platform" do
      create(:lti_context, :lti1p3, lti_platform: platform, context_id: "c1")

      expect(build(:lti_context, :lti1p3, lti_platform: platform, context_id: "c1")).not_to be_valid
    end

    it "allows the same context_id on two platforms" do
      create(:lti_context, :lti1p3, lti_platform: platform, context_id: "c1")

      expect(build(:lti_context, :lti1p3, lti_platform: create(:lti_platform), context_id: "c1")).to be_valid
    end

    it "has a database index that rejects the same context_id twice on one platform" do
      create(:lti_context, :lti1p3, lti_platform: platform, context_id: "c1")
      duplicate = build(:lti_context, :lti1p3, lti_platform: platform, context_id: "c1")

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe LtiPlatform do
    it "owns its users and courses, and removes them with the platform" do
      create(:lti_user, :lti1p3, lti_platform: platform)
      create(:lti_context, :lti1p3, lti_platform: platform)

      expect(platform.lti_users.count).to eq(1)
      expect(platform.lti_contexts.count).to eq(1)
      expect { platform.destroy }.to change(LtiUser, :count).by(-1).and change(LtiContext, :count).by(-1)
    end
  end

  it "leaves the 1.1 rows working" do
    expect(build(:lti_user)).to be_valid
    expect(build(:lti_context)).to be_valid
  end
end
