module Lti1p3
  class Roles
    def initialize(params)
      @params = params
    end

    ROLES_CLAIM = "https://purl.imsglobal.org/spec/lti/claim/roles".freeze

    def names
      @names ||= claim_values
        .map { |uri| name_from(uri.to_s.strip) }
        .reject(&:empty?)
        .uniq
    end

    def instructor? = names.include?("Instructor")
    def learner? = names.include?("Learner")
    def administrator? = names.include?("Administrator")
    def teaching_assistant? = names.include?("TeachingAssistant")
    def can_create_polls? = instructor? || teaching_assistant?

    private

    def claim_values
      claim = @params[ROLES_CLAIM]
      claim.is_a?(Array) ? claim : []
    end

    def name_from(uri)
      separator = uri.include?("#") ? "#" : "/"
      uri.rpartition(separator).last.strip
    end
  end
end
