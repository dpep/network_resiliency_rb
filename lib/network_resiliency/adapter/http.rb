require "net/http"

module NetworkResiliency
  module Adapter
    module HTTP
      extend self

      def patch(instance = nil)
        return if patched?(instance)

        (instance&.singleton_class || Net::HTTP).prepend(Instrumentation)
      end

      def patched?(instance = nil)
        (instance&.singleton_class || Net::HTTP).ancestors.include?(Instrumentation)
      end

      module Instrumentation
        def connect
          return super unless NetworkResiliency.enabled?(:http)
          original_timeout = self.open_timeout

          timeouts = NetworkResiliency.timeouts_for(
            adapter: "http",
            action: "connect",
            destination: address,
            max: original_timeout,
            units: :seconds,
          )

          attempts = 0
          ts = -NetworkResiliency.timestamp

          begin
            attempts += 1
            error = nil

            self.open_timeout = timeouts.shift

            super
          rescue Net::OpenTimeout => e
            # capture error
            error = e.class

            retry if timeouts.size > 0

            raise
          ensure
            ts += NetworkResiliency.timestamp
            self.open_timeout = original_timeout

            NetworkResiliency.record(
              adapter: "http",
              action: "connect",
              destination: address,
              error: error,
              duration: ts,
              timeout: self.open_timeout * 1_000,
              attempts: attempts,
            )
          end
        end
      end
    end
  end
end
