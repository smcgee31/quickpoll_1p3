module Lti
  class JwksController < BaseController
    def show
      keys = LtiRegistration.all.map(&:public_jwk)
      render json: { keys: }
    end
  end
end
