FactoryBot.define do
  factory :lti_platform do
    sequence(:issuer) { |n| "https://canvas-#{n}.example.test" }
    name { "Test Canvas" }
    auth_endpoint { "#{issuer}/api/lti/authorize_redirect" }
    token_endpoint { "#{issuer}/login/oauth2/token" }
    jwks_uri { "#{issuer}/api/lti/security/jwks" }
  end

  factory :lti_registration do
    lti_platform
    sequence(:client_id) { |n| "1000000000000#{n}" }
  end

  factory :lti_deployment do
    lti_registration
    sequence(:deployment_id) { |n| "#{n}:8865aa05b4b79b64a91a86042e43af5ea8ae79eb" }
  end
end

FactoryBot.define do
  factory :lti_launch_state do
    lti_registration
    sequence(:state) { |n| "state-#{n}" }
    sequence(:nonce) { |n| "nonce-#{n}" }
  end
end

# Rows that belong to a platform (1.3) instead of a consumer (1.1).
# FactoryBot.modify adds a trait to a factory that lti.rb already defined.
FactoryBot.modify do
  factory :lti_user do
    trait :lti1p3 do
      lti_consumer { nil }
      lti1p1_user_id { nil }
      lti_platform
      sequence(:lti1p3_sub) { |n| "sub-#{n}" }
    end
  end

  factory :lti_context do
    trait :lti1p3 do
      lti_consumer { nil }
      lti_platform
    end
  end
end
