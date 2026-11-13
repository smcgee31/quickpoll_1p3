module Lti1p3
  class PlatformKeys
    # What to build: app/services/lti1p3/platform_keys.rb
    #   - Lti1p3::PlatformKeys.fetch(platform) is a CLASS method. It returns the "keys" array from the JSON
    #     at platform.jwks_uri: an array of hashes, one per key. Do not turn them into objects here.
    #   - Download with `Net::HTTP.get_response(URI(platform.jwks_uri))`. The spec stubs exactly that call.
    #   - Raise Lti1p3::PlatformKeys::Unavailable (a StandardError) for every way this can go wrong:
    #       * the answer is not a success (Net::HTTPSuccess)
    #       * the body is not JSON
    #       * the JSON has no "keys" array
    #       * the request itself fails: SocketError, Timeout::Error, SystemCallError (connection refused)

    class Unavailable < StandardError; end

    def self.fetch(platform)
      begin
        response = Net::HTTP.get_response(URI(platform.jwks_uri))
        raise Unavailable unless response.is_a?(Net::HTTPSuccess)

        body = JSON.parse(response.body)
        raise Unavailable unless body.is_a?(Hash)

        keys = body["keys"]
        raise Unavailable unless keys.is_a?(Array)

        keys

      rescue SocketError, Timeout::Error, SystemCallError, JSON::ParserError
        raise Unavailable
      end
    end
  end
end
