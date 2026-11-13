module Lti
  class LoginController < BaseController
    def create
      platform = LtiPlatform.find_by(issuer: params[:iss])
      registration = platform&.lti_registrations&.find_by(client_id: params[:client_id])

      if platform.nil? || registration.nil? || params[:login_hint].blank?
        return head :bad_request
      end

      state = SecureRandom.hex(16)
      nonce = SecureRandom.hex(16)
      registration.lti_launch_states.create!(lti_registration: registration, state: state, nonce: nonce)

      query = {
        scope: "openid",
        response_type: "id_token",
        response_mode: "form_post",
        prompt: "none",
        client_id: registration.client_id,
        redirect_uri: "#{Rails.configuration.x.public_base_url}/lti/launch",
        login_hint: params[:login_hint],
        lti_message_hint: params[:lti_message_hint].presence,
        state: state,
        nonce: nonce
      }.compact

      redirect_to "#{platform.auth_endpoint}?#{query.to_query}", allow_other_host: true
    end
  end
end
