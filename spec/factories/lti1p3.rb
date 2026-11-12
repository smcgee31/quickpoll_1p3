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
