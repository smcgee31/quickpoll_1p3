namespace :lti do
  # The local Canvas (inst-cli, host canvas-web.inseng.test). Its issuer is always
  # https://canvas.instructure.com, from lti_iss in canvas-lms/config/security.yml.
  # The browser calls auth_endpoint. This container calls jwks_uri, so both must resolve here.
  desc "Create the LtiPlatform row for the local Canvas (safe to run twice)"
  task platform: :environment do
    domain = ENV.fetch("INST_DOMAIN", "inseng.test")
    canvas = "http://canvas-web.#{domain}"

    platform = LtiPlatform.find_or_initialize_by(issuer: "https://canvas.instructure.com")
    platform.update!(
      name: "Local Canvas",
      auth_endpoint: "#{canvas}/api/lti/authorize_redirect",
      token_endpoint: "#{canvas}/login/oauth2/token",
      jwks_uri: "#{canvas}/api/lti/security/jwks"
    )
    puts "Platform #{platform.id}: #{platform.issuer}"
  end

  # CLIENT_ID is the long number from the "Copy Client ID" button on the Canvas app page, like
  # 10000000000011. Not the short key id (11) in the URL. The launch sends the long one as `aud`.
  # DEPLOYMENT_ID is the deployment id Canvas shows for the installed tool (like 1:abc...).
  desc "Create the registration and deployment: rake lti:register CLIENT_ID=... DEPLOYMENT_ID=..."
  task register: :platform do
    client_id = ENV.fetch("CLIENT_ID") { abort "Set CLIENT_ID=<developer key id>" }
    deployment_id = ENV.fetch("DEPLOYMENT_ID") { abort "Set DEPLOYMENT_ID=<deployment id from Canvas>" }

    platform = LtiPlatform.find_by!(issuer: "https://canvas.instructure.com")
    registration = platform.lti_registrations.find_or_create_by!(client_id: client_id)
    deployment = registration.lti_deployments.find_or_create_by!(deployment_id: deployment_id)
    puts "Registration #{registration.id} (client_id #{registration.client_id}), deployment #{deployment.deployment_id}"
  end
end
