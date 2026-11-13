module Lti1p3
  # Turns a verified 1.3 launch into two rows: the person (LtiUser) and the course (LtiContext).
  # The 1.3 twin of Lti1p1::LaunchRecords. Call it only after Lti1p3::LaunchVerifier#call returned
  # true. It trusts the claims, including the presence of "sub" and the context "id".
  #
  #   records = Lti1p3::LaunchRecords.new(platform: platform, claims: verifier.claims)
  #   records.call      # true. It saves both rows in one transaction.
  #   records.user      # the LtiUser
  #   records.context   # the LtiContext
  class LaunchRecords
    CONTEXT_CLAIM = LaunchVerifier::CONTEXT_CLAIM

    attr_reader :user, :context

    def initialize(platform:, claims:)
      @platform = platform
      @claims = claims
    end

    def call
      # One transaction: if the context fails to save, the user is not left behind.
      ActiveRecord::Base.transaction do
        @user = save_user
        @context = save_context
      end
      true
    end

    private

    def save_user
      user = @platform.lti_users.find_or_initialize_by(lti1p3_sub: @claims["sub"])
      # A launch with no name must not erase a name we already have.
      user.name = @claims["name"].presence || user.name
      user.save!
      user
    end

    def save_context
      claim = @claims[CONTEXT_CLAIM]
      context = @platform.lti_contexts.find_or_initialize_by(context_id: claim["id"])
      context.title = claim["title"].presence || context.title
      context.label = claim["label"].presence || context.label
      context.save!
      context
    end
  end
end
