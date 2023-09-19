require "net/http"

module NetworkResiliency
  module Adapter
    module HTTP
      extend self

      def patch(instance = nil)
        (instance&.singleton_class || Net::HTTP).prepend(Instrumentation)
      end

      def patched?(instance = nil)
        (instance&.singleton_class || Net::HTTP).ancestors.include?(Instrumentation)
      end

      module Instrumentation
        def connect
          return super unless NetworkResiliency.enabled?

          begin
            ts = -NetworkResiliency.timestamp

            super
          rescue Net::OpenTimeout => e
            # capture error
            raise
          ensure
            ts += NetworkResiliency.timestamp

            NetworkResiliency.statsd&.distribution(
              "network_resiliency.http.connect",
              ts,
              tags: {
                destination: address,
                error: e&.class,
              }.compact,
            )
          end
        end
      end
    end
  end
end
