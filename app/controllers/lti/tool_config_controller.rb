module Lti
  class ToolConfigController < BaseController
    def show
      base = Rails.configuration.x.public_base_url

      config = {
        "title": "QuickPoll 1.3",
        "description": "QuickPoll 1.3 LTI Tool",
        "oidc_initiation_url": "#{base}/lti/login",
        "target_link_uri": "#{base}/lti/launch",
        "redirect_uris": [ "#{base}/lti/launch" ],
        "public_jwk_url": "#{base}/lti/jwks",
        "scopes": [],
        "extensions": [ {
          "platform": "canvas.instructure.com",
          "privacy_level": "public",
          "settings": { "placements": [ {
            "placement": "course_navigation",
            "message_type": "LtiResourceLinkRequest",
            "text": "QuickPoll 1.3",
            "target_link_uri": "#{base}/lti/launch"
          } ] }
        } ]
      }

      render json: config
    end
  end
end
