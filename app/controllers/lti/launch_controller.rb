module Lti
  class LaunchController < BaseController
    before_action :verify_launch, unless: :lti1p3_launch?

    def create
      lti1p3_launch? ? launch_1p3 : launch_1p1
    end

    private

    def launch_1p3
      verifier = Lti1p3::LaunchVerifier.new(
        id_token: params[:id_token],
        state: params[:state]
      )
      return reject(verifier.error) unless verifier.call

      records = Lti1p3::LaunchRecords.new(
        platform: verifier.registration.lti_platform,
        claims: verifier.claims
      )
      records.call

      reset_session
      session[:lti_user_id] = records.user.id
      session[:lti_context_id] = records.context.id

      redirect_to lti_polls_path, status: :see_other
    end

    def verify_launch
      @consumer = LtiConsumer.find_by(consumer_key: request.request_parameters["oauth_consumer_key"])
      return reject(:unknown_consumer) if @consumer.nil?

      verifier = Lti1p1::SignatureVerifier.new(
        method: request.method,
        url: "#{Rails.configuration.x.public_base_url}#{request.fullpath}",
        params: request.request_parameters,
        secret: @consumer.shared_secret
      )
      return reject(:bad_signature) unless verifier.valid?

      guard = Lti1p1::ReplayGuard.new(consumer: @consumer, params: request.request_parameters)
      reject(guard.error) unless guard.accept?
    end

    def reject(reason)
      Rails.logger.warn("[lti launch] rejected: #{reason}")
      render plain: "Launch rejected.", status: :unauthorized
    end

    def launch_1p1
      records = Lti1p1::LaunchRecords.new(consumer: @consumer, params: request.request_parameters)

      if records.call
        reset_session
        session[:lti_user_id] = records.user.id
        session[:lti_context_id] = records.context.id
        session[:can_create_polls] = Lti1p1::Roles.new(request.request_parameters).can_create_polls?

        redirect_to lti_polls_path, status: :see_other
      else
        Rails.logger.warn("[lti launch] rejected: #{records.error}")
        render plain: "Launch failed.", status: :bad_request
      end
    end

    def lti1p3_launch?
      request.request_parameters["id_token"].present?
    end
  end
end
