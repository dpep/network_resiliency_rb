module NetworkResiliency
  module Adapter
    module HTTP
      extend self

      def library
        "net/http"
      end

      def target
        Net::HTTP
      end

      def patch(instance = nil)
        require library

        (instance&.singleton_class || target).prepend(Instrumentation)
      end

      def patched?(instance = nil)
        (instance&.singleton_class || target).ancestors.include?(Instrumentation)
      end

      module Instrumentation
        def connect
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
