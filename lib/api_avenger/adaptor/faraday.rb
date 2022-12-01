require "faraday"

module ApiAvenger
  module Adapter
    class Faraday < ::Faraday::Middleware
      def on_request(env)
        puts "on_request to: #{env.url}"
      end

      def on_complete(env)
        puts "on_complete"
      end
    end
  end
end

Faraday::Request.register_middleware(
  api_avenger: ApiAvenger::Adapter::Faraday,
)
