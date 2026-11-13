module Lti1p3
  # Decides whether an LTI 1.3 launch is real. See spec/services/lti1p3/launch_verifier_spec.rb for the rules.
  #
  #   verifier = Lti1p3::LaunchVerifier.new(id_token: params[:id_token], state: params[:state])
  #   verifier.call   # true or false. Never raises for a bad launch.
  #   verifier.error  # nil, or a Symbol that says which check failed
  class LaunchVerifier
    # Raised inside the checks and rescued in #call, so a bad launch is a `false`, not an exception.
    class Refused < StandardError
      attr_reader :reason

      def initialize(reason)
        @reason = reason
        super(reason.to_s)
      end
    end

    STATE_LIFETIME = 10.minutes
    # How far ahead of our clock the platform's clock may be before we call the token "from the future".
    CLOCK_SKEW = 60.seconds
    CLAIM_BASE = "https://purl.imsglobal.org/spec/lti/claim".freeze
    CONTEXT_CLAIM = "#{CLAIM_BASE}/context".freeze
    SUPPORTED_MESSAGE_TYPE = "LtiResourceLinkRequest".freeze
    SUPPORTED_VERSION = "1.3.0".freeze

    attr_reader :error, :claims, :registration, :deployment

    def initialize(id_token:, state:)
      @id_token = id_token
      @state = state
    end

    def call
      @error = nil
      check_params_present
      load_launch_state
      keys = fetch_platform_keys
      @claims = decode_token(keys)
      check_required_claims
      check_issuer_and_audience
      check_times
      check_launch_details
      use_up_state
      true
    rescue Refused => e
      @error = e.reason
      false
    end

    private

    def fail!(reason)
      raise Refused, reason
    end

    # Steps 1 and 2. Cheap checks first, before any database or network work.
    def check_params_present
      fail!(:missing_state) if @state.blank?
      fail!(:missing_id_token) if @id_token.blank?
    end

    # Steps 3, 4 and 5. The state is the string we handed out in the OIDC login. It is our only link
    # between this launch and the registration (and so the platform and keys) it belongs to.
    def load_launch_state
      @launch_state = LtiLaunchState.find_by(state: @state)
      fail!(:unknown_state) if @launch_state.nil?
      fail!(:state_used) if @launch_state.used_at.present?
      fail!(:state_expired) if @launch_state.created_at < STATE_LIFETIME.ago

      @registration = @launch_state.lti_registration
    end

    # Step 6. The public keys of the platform, as an Array of JWK hashes.
    def fetch_platform_keys
      PlatformKeys.fetch(@registration.lti_platform)
    rescue PlatformKeys::Unavailable
      fail!(:keys_unavailable)
    end

    # Step 7. Check the signature and return the claims.
    # The kid in the token header picks the key out of the set. [:RS256] is the only algorithm we accept,
    # so a token that claims "alg: none" or HS256 is refused even if it is otherwise well formed.
    def decode_token(keys)
      JSON::JWT.decode(@id_token, JSON::JWK::Set.new(keys), [ :RS256 ])
    rescue JSON::JWT::InvalidFormat
      fail!(:malformed_token)
    rescue JSON::JWT::Exception
      fail!(:bad_signature)
    end

    # Step 8, first half. The signature only proves who wrote the claims. These checks prove the claims
    # are about us, about now, and complete enough to use.
    def check_required_claims
      fail!(:missing_claim) if %w[exp iat sub].any? { |name| @claims[name].blank? }

      context = @claims[CONTEXT_CLAIM]
      fail!(:missing_claim) unless context.is_a?(Hash) && context["id"].present?
    end

    def check_issuer_and_audience
      fail!(:wrong_issuer) unless @claims["iss"] == @registration.lti_platform.issuer
      # aud is a String, or an Array of Strings when the token has more than one audience.
      fail!(:wrong_audience) unless Array(@claims["aud"]).include?(@registration.client_id)
    end

    def check_times
      now = Time.current.to_i
      fail!(:expired) if @claims["exp"].to_i <= now
      fail!(:issued_in_future) if @claims["iat"].to_i > now + CLOCK_SKEW.to_i
    end

    # Step 8, second half. Is this the launch we asked for, of a kind we handle, from a deployment we know?
    def check_launch_details
      # The nonce ties this token to the login that started it. The state row holds the one we saved.
      fail!(:wrong_nonce) unless @claims["nonce"] == @launch_state.nonce
      fail!(:unsupported_message_type) unless @claims["#{CLAIM_BASE}/message_type"] == SUPPORTED_MESSAGE_TYPE
      fail!(:unsupported_version) unless @claims["#{CLAIM_BASE}/version"] == SUPPORTED_VERSION

      # Look only among the deployments of THIS registration. A deployment id from another one is unknown.
      @deployment = @registration.lti_deployments.find_by(deployment_id: @claims["#{CLAIM_BASE}/deployment_id"])
      fail!(:unknown_deployment) if @deployment.nil?
    end

    # Step 9. Last, so a launch that fails any check leaves its state alone.
    # One conditional UPDATE lets the database pick a single winner when two requests arrive together.
    # Reading used_at first and writing after would let both requests see nil and both succeed.
    def use_up_state
      updated = LtiLaunchState.where(id: @launch_state.id, used_at: nil).update_all(used_at: Time.current)
      fail!(:state_used) if updated.zero?
    end
  end
end
