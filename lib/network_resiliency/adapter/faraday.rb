gem "faraday", "~> 1.10"
require "faraday"

module NetworkResiliency
  module Adapter
    class Faraday < ::Faraday::Adapter::NetHttp
      def build_connection(env)
        super.tap do |conn|
          unless NetworkResiliency::Adapter::HTTP.patched?(conn)
            NetworkResiliency::Adapter::HTTP.patch(conn)
          end
        end
      end
    end
  end
end

Faraday::Adapter.register_middleware(
  network_resiliency: NetworkResiliency::Adapter::Faraday,
)
