require "faraday"

module ApiAvenger
  module Adaptor
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
